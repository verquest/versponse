# frozen_string_literal: true

module Versponse
  module Properties
    # A value from a fixed list
    #
    # @api private
    class Enum < Base
      # Ruby classes a value of each built-in type must be
      VALUE_CLASSES = {
        "string" => [::String],
        "number" => [::Numeric],
        "integer" => [::Integer],
        "boolean" => [::TrueClass, ::FalseClass],
        "object" => [::Hash]
      }.freeze

      # @param values [Array] allowed values, each of the type
      # @param type [Symbol, String, Array<Symbol, String>, nil] a built-in type, a custom one (only its base type is used, its
      #   schema options would duplicate or contradict the values) or a union of built-in types; required
      # @param options [Hash] see {Base#initialize}
      # @raise [Versponse::DefinitionError] when values is empty, type is missing or unknown, or a value isn't of the type
      def initialize(values:, type: nil, **options)
        super(**options)
        raise DefinitionError, "#{key}: values must be a non-empty Array" unless values.is_a?(::Array) && !values.empty?
        raise DefinitionError, "#{key}: enum needs type: (one of #{FieldType::BUILT_IN.join(", ")}, a custom type or a union)" if type.nil?

        @type = FieldType.resolve(type, key).first
        @values = values.dup.freeze
        check_values!
      end

      # @param context [Versponse::SchemaContext, nil] schema generation context
      # @return [Hash] JSON Schema of the enum; nullable adds "null" to type and nil to the values, or nullable: true
      #   in OpenAPI 3.0 documents, where a type union is an anyOf of single types
      def schema(context)
        options = {"enum" => @values}.merge(schema_options)
        return nullable_type(FieldType.openapi30_union(@type, options), context) if openapi30_union?(@type, context)

        schema = nullable_type({"type" => @type}.merge(options), context)
        (nullable? && !nullable_keyword?(context)) ? schema.merge("enum" => @values | [nil]) : schema
      end

      # @param version [String] unused by scalars
      # @return [Versponse::Steps::Value] compiled step
      def step(version:)
        value_step
      end

      private

      def check_values!
        types = Array(@type)
        invalid = @values.find { |value| !(value.nil? && nullable?) && !matches?(value, types) }
        return if invalid.nil? && (nullable? || !@values.include?(nil))

        raise DefinitionError, "#{key}: enum value #{invalid.inspect} is not of type #{types.join(" or ")}"
      end

      def matches?(value, types)
        types.any? { |type| VALUE_CLASSES.fetch(type).any? { |klass| value.is_a?(klass) } }
      end
    end
  end
end
