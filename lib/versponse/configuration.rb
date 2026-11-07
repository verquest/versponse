# frozen_string_literal: true

module Versponse
  # Settings for Versponse, changed with {Versponse.configure}
  #
  # Plans and schemas are cached. Setting json_schema_version, formatters, version_resolver, field_order
  # or default_additional_properties on {Versponse.configuration} resets them; custom_field_types resolve
  # when properties are defined, so set them before response classes load.
  #
  # @example
  #   Versponse.configure do |config|
  #     config.current_version = -> { Current.api_version }
  #     config.validate_output = Rails.env.local?
  #   end
  class Configuration
    # Supported JSON Schema versions and their json_schemer modules, the same as verquest's
    SCHEMAS = {
      draft4: :Draft4,
      draft6: :Draft6,
      draft7: :Draft7,
      draft2019_09: :Draft201909,
      draft2020_12: :Draft202012,
      openapi30: :OpenAPI30,
      openapi31: :OpenAPI31
    }.freeze

    # JSON Schema versions without the `const` keyword, as in verquest
    VERSIONS_WITHOUT_CONST = %i[draft4 openapi30].freeze

    # How each JSON Schema version names a schema for "#Name" references: $anchor from 2019-09,
    # a plain-name $id in drafts 6 and 7, and id in draft 4 (which OpenAPI 3.0 is based on)
    ANCHOR_KEYWORDS = {draft4: "id", openapi30: "id", draft6: "$id", draft7: "$id"}.freeze

    # @return [Boolean, #call] validate every rendered response against its schema, none (default false), or those
    #   for which the callable, called with the response class, returns a truthy value
    attr_reader :validate_output
    # @return [Numeric] share of renders validated when validate_output allows it, from 0 to 1 (default 1.0)
    attr_reader :validate_output_sample_rate
    # @return [Boolean] additionalProperties of generated object schemas (default false)
    attr_reader :default_additional_properties
    # @return [#call, nil] returns the version used when serialize gets no version:
    attr_reader :current_version
    # @return [#call] resolves a requested version from the declared ones; it must return the closest
    #   declared version at or before the request (it may add rules, e.g. preview sorting highest),
    #   because requested versions are canonicalized against all declared names before caching
    attr_reader :version_resolver
    # @return [#call] turns a Hash into a JSON String
    attr_reader :json_generator
    # @return [Hash{String => #call}] formatters keyed by JSON Schema format
    attr_reader :formatters
    # @return [Symbol] JSON Schema version of generated schemas (default :openapi31)
    attr_reader :json_schema_version
    # @return [Symbol] :raise (default) or :ignore for expand paths that match no expandable association
    attr_reader :unknown_expand
    # @return [Symbol] :declaration (default) or :alphabetical (identifiers first, then by output key,
    #   like blueprinter's sort_fields_by :name_asc)
    attr_reader :field_order
    # @return [Hash{String => Hash}] custom field types, normalized by {FieldType.normalize} (default {})
    attr_reader :custom_field_types

    # @return [Configuration] configuration with default settings
    def initialize
      @validate_output = false
      @validate_output_sample_rate = 1.0
      @default_additional_properties = false
      @json_schema_version = :openapi31
      @unknown_expand = :raise
      @field_order = :declaration
      @version_resolver = VersionResolver
      @json_generator = JSON.method(:generate)
      @formatters = Formatters::DEFAULTS
      @custom_field_types = {}.freeze
    end

    # @param value [Boolean, #call] validate every render, none, or those for which value.call(response_class) is
    #   truthy (called per render, e.g. to read Rails' Current)
    # @raise [ArgumentError] for anything else, or a lambda or Method that can't take the response class
    def validate_output=(value)
      @validate_output = (value == true || value == false) ? value : validate_output_callable!(value)
    end

    # @param value [Numeric] share of renders validated when validate_output allows it, from 0 to 1
    # @raise [ArgumentError] for anything but a real number from 0 to 1
    def validate_output_sample_rate=(value)
      unless value.is_a?(Numeric) && value.real? && (0..1).cover?(value)
        raise ArgumentError, "validate_output_sample_rate must be a number from 0 to 1"
      end

      @validate_output_sample_rate = value
    end

    # @param value [Boolean] additionalProperties of generated object schemas
    # @raise [ArgumentError] for a value that isn't true or false
    def default_additional_properties=(value)
      @default_additional_properties = boolean!(value, :default_additional_properties)
      changed!
    end

    # @param value [#call, nil] returns the current version, or nil to clear it
    # @raise [ArgumentError] when value does not respond to call
    def current_version=(value)
      @current_version = value.nil? ? nil : callable!(value, :current_version)
    end

    # @param value [#call] called with (requested_version, sorted_versions); must return the closest
    #   declared version at or before the request, since requests are canonicalized against all declared names
    # @raise [ArgumentError] when value does not respond to call
    def version_resolver=(value)
      @version_resolver = callable!(value, :version_resolver)
      changed!
    end

    # @param value [#call] called with the rendered Hash, returns a String
    # @raise [ArgumentError] when value does not respond to call
    def json_generator=(value)
      @json_generator = callable!(value, :json_generator)
    end

    # @param value [Symbol] one of {SCHEMAS}
    # @raise [ArgumentError] when the version is not supported
    def json_schema_version=(value)
      raise ArgumentError, "Unsupported JSON Schema version: #{value}. Use one of #{SCHEMAS.keys.join(", ")}" unless SCHEMAS.key?(value)

      @json_schema_version = value
      changed!
    end

    # @param value [Symbol] :raise or :ignore
    # @raise [ArgumentError] for any other value
    def unknown_expand=(value)
      raise ArgumentError, "unknown_expand must be :raise or :ignore" unless %i[raise ignore].include?(value)

      @unknown_expand = value
    end

    # @param value [Symbol] :declaration or :alphabetical
    # @raise [ArgumentError] for any other value
    def field_order=(value)
      raise ArgumentError, "field_order must be one of #{FieldOrder::VALUES.join(", ")}" unless FieldOrder::VALUES.include?(value)

      @field_order = value
      changed!
    end

    # @param value [Hash{String, Symbol => #call}] formatters keyed by JSON Schema format
    # @raise [ArgumentError] when a formatter does not respond to call
    def formatters=(value)
      raise ArgumentError, "formatters must be a Hash of callables" unless value.is_a?(Hash) && value.each_value.all? { |formatter| formatter.respond_to?(:call) }

      @formatters = value.transform_keys(&:to_s).freeze
      changed!
    end

    # Types resolve when a field is defined, so set them before response classes load
    #
    # @param value [Hash{Symbol, String => Hash}] verquest-shaped types, e.g. {site_id: {type: "string", schema_options: {pattern: "^site_"}}}
    # @raise [ArgumentError] when value is not a Hash or a type is invalid
    def custom_field_types=(value)
      raise ArgumentError, "custom_field_types must be a Hash" unless value.is_a?(Hash)

      @custom_field_types = value.to_h { |name, definition| [name.to_s, FieldType.normalize(name, definition)] }.freeze
    end

    # @return [Boolean] true when nullable is written as `nullable: true` (OpenAPI 3.0)
    def nullable_keyword?
      json_schema_version == :openapi30
    end

    # @return [Boolean] false when constants are written as a one-value enum (draft 4 and OpenAPI 3.0)
    def const_keyword?
      !VERSIONS_WITHOUT_CONST.include?(json_schema_version)
    end

    # @param name [String] anchor name
    # @return [Hash{String => String}] the keyword naming a schema so "#<name>" references it
    def anchor(name)
      keyword = ANCHOR_KEYWORDS[json_schema_version]
      keyword ? {keyword => "##{name}"} : {"$anchor" => name}
    end

    # @return [String] meta-schema URI of the configured JSON Schema version
    def json_schema_uri
      require "json_schemer"

      JSONSchemer.const_get(SCHEMAS.fetch(json_schema_version))::BASE_URI.to_s
    end

    private

    # Only the global configuration feeds the caches
    def changed!
      Versponse.reset_caches! if Versponse.configuration.equal?(self)
    end

    def boolean!(value, name)
      raise ArgumentError, "#{name} must be true or false" unless [true, false].include?(value)

      value
    end

    # Lambdas and Methods check their arity, so one that can't take the response class fails here, not on a render
    def validate_output_callable!(value)
      raise ArgumentError, "validate_output must be true, false or respond to call" unless value.respond_to?(:call)
      strict = value.is_a?(Method) || (value.is_a?(Proc) && value.lambda?)
      return value unless strict

      types = value.parameters.map(&:first)
      required = types.count(:req)
      positional = required == 1 || (required.zero? && types.intersect?(%i[opt rest]))
      raise ArgumentError, "validate_output must accept the response class" unless positional && !types.include?(:keyreq)

      value
    end

    def callable!(value, name)
      raise ArgumentError, "#{name} must respond to call" unless value.respond_to?(:call)

      value
    end
  end
end
