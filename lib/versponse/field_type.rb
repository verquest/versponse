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

    # @param type [Symbol, String] built-in or custom type name
    # @param key [String] property key, for the error message
    # @return [Array(String, Hash)] the base type and the custom type's schema options
    # @raise [Versponse::DefinitionError] for an unknown type
    def self.resolve(type, key)
      type = type.to_s
      return [type, {}] if BUILT_IN.include?(type)

      custom = Versponse.configuration.custom_field_types.fetch(type) do
        raise DefinitionError, "#{key}: type must be one of #{names.join(", ")}"
      end
      custom.values_at("type", "schema_options")
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
