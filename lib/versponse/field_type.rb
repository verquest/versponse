# frozen_string_literal: true

module Versponse
  # Built-in field types, and custom ones from config.custom_field_types in verquest's shape
  #
  # @api private
  module FieldType
    # Built-in types; "object" is a free-form map whose value passes through
    BUILT_IN = %w[string number integer boolean object].freeze

    # Keys of a custom type definition; required: is accepted for verquest and ignored
    KEYS = %i[type schema_options required].freeze

    # @param name [Symbol, String] custom type name
    # @param definition [Hash] type: and schema_options: (required: is ignored)
    # @return [Hash{String => Object}] frozen {"type" => base type, "schema_options" => camelized keywords}
    # @raise [ArgumentError] for a built-in name, unknown keys or an unsupported type:
    def self.normalize(name, definition)
      definition = check!(name.to_s, definition)
      options = (definition[:schema_options] || {}).transform_values { |value| value.is_a?(Regexp) ? value.source : value }
      DeepFreeze.call({"type" => definition[:type].to_s, "schema_options" => Naming.camelize_keys(options)})
    end

    # @param type [Symbol, String, Array<Symbol, String>] built-in or custom type name, or a union of built-in types
    # @param key [String] property key, for the error message
    # @return [Array(String, Hash), Array(Array<String>, Hash)] the base type (or the union's types) and the custom type's schema options
    # @raise [Versponse::DefinitionError] for an unknown type or an invalid union
    def self.resolve(type, key)
      return [union(type, key), {}] if type.is_a?(Array)

      type = type.to_s
      return [type, {}] if BUILT_IN.include?(type)

      custom = Versponse.configuration.custom_field_types.fetch(type) do
        raise DefinitionError, "#{key}: type must be one of #{names.join(", ")}"
      end
      custom.values_at("type", "schema_options")
    end

    # Null comes from nullable:, and custom types can't take part, because their schema options would apply to every type
    #
    # @param types [Array<Symbol, String>] two or more distinct built-in types
    # @param key [String] property key, for the error message
    # @return [Array<String>] frozen type names in declaration order, without duplicates
    # @raise [Versponse::DefinitionError] for fewer than two distinct types, or a type that isn't built in
    def self.union(types, key)
      names = types.map(&:to_s).uniq
      invalid = names - BUILT_IN
      raise DefinitionError, "#{key}: type unions take only built-in types (#{BUILT_IN.join(", ")}), not #{invalid.join(", ")}" unless invalid.empty?
      raise DefinitionError, "#{key}: a type union needs at least two distinct types" if names.size < 2

      names.freeze
    end

    # The union's anyOf and a declared anyOf can't share the anyOf key, so both go under allOf
    #
    # OpenAPI 3.0's nullable only applies next to a type, so a nullable union sets it on each branch
    #
    # @param types [Array<String>] union types
    # @param options [Hash{String => Object}] the property's (or its items') schema keywords
    # @param nullable [Boolean] whether null is allowed
    # @return [Hash] OpenAPI 3.0 schema: an anyOf of single types with the keywords alongside
    def self.openapi30_union(types, options, nullable: false)
      branch = nullable ? {"nullable" => true} : {}
      union = {"anyOf" => types.map { |type| {"type" => type}.merge(branch) }}
      return union.merge(options) unless options.key?("anyOf")

      {"allOf" => [union, {"anyOf" => options["anyOf"]}]}.merge(options.except("anyOf"))
    end

    # @return [Array<String>] built-in and custom type names
    def self.names
      BUILT_IN + Versponse.configuration.custom_field_types.keys
    end

    def self.check!(name, definition)
      raise ArgumentError, "Custom field type #{name} shadows a built-in type" if BUILT_IN.include?(name)
      raise ArgumentError, "Custom field type #{name} must be a Hash" unless definition.is_a?(Hash)

      definition.transform_keys(&:to_sym).tap { |symbolized| check_keys!(name, symbolized) }
    end

    def self.check_keys!(name, definition)
      unknown = definition.keys - KEYS
      raise ArgumentError, "Custom field type #{name} has unknown keys: #{unknown.join(", ")}" unless unknown.empty?
      raise ArgumentError, "Custom field type #{name} needs type: one of #{BUILT_IN.join(", ")}" unless BUILT_IN.include?(definition[:type].to_s)
    end

    private_class_method :check!, :check_keys!
  end
end
