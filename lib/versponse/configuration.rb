# frozen_string_literal: true

module Versponse
  # Settings for Versponse, changed with {Versponse.configure}
  #
  # Plans and schemas are cached, so change settings at boot. Call {Versponse.reset_caches!}
  # after changing them later (tests do this through ConfigurationTestHelper).
  #
  # @example
  #   Versponse.configure do |config|
  #     config.current_version = -> { Current.api_version }
  #     config.validate_output = Rails.env.local?
  #   end
  class Configuration
    # Supported JSON Schema versions and their json_schemer modules
    SCHEMAS = {
      draft2020_12: :Draft202012,
      draft2019_09: :Draft201909,
      draft7: :Draft7,
      openapi30: :OpenAPI30,
      openapi31: :OpenAPI31
    }.freeze

    # @return [Boolean] validate every rendered response against its schema (default false)
    attr_accessor :validate_output
    # @return [Boolean] additionalProperties of generated object schemas (default false)
    attr_accessor :default_additional_properties
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

    # @return [Configuration] configuration with default settings
    def initialize
      @validate_output = false
      @default_additional_properties = false
      @json_schema_version = :openapi31
      @version_resolver = VersionResolver
      @json_generator = JSON.method(:generate)
      @formatters = Formatters::DEFAULTS
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
    end

    # @param value [Hash{String, Symbol => #call}] formatters keyed by JSON Schema format
    # @raise [ArgumentError] when a formatter does not respond to call
    def formatters=(value)
      raise ArgumentError, "formatters must be a Hash of callables" unless value.is_a?(Hash) && value.each_value.all? { |formatter| formatter.respond_to?(:call) }

      @formatters = value.transform_keys(&:to_s).freeze
    end

    # @return [Boolean] true when nullable is written as `nullable: true` (OpenAPI 3.0)
    def nullable_keyword?
      json_schema_version == :openapi30
    end

    # @return [Boolean] false when constants are written as a one-value enum (OpenAPI 3.0)
    def const_keyword?
      json_schema_version != :openapi30
    end

    # @return [String] meta-schema URI of the configured JSON Schema version
    def json_schema_uri
      require "json_schemer"

      JSONSchemer.const_get(SCHEMAS.fetch(json_schema_version))::BASE_URI.to_s
    end

    private

    def callable!(value, name)
      raise ArgumentError, "#{name} must respond to call" unless value.respond_to?(:call)

      value
    end
  end
end
