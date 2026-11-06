# frozen_string_literal: true

module Versponse
  module Properties
    # A value from a fixed list
    #
    # @api private
    class Enum < Base
      # @return [Array<String>] keywords this property type writes itself
      def self.written_keywords = %w[enum].freeze

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
      #   schema options would duplicate or contradict the values) or a union of built-in types; nil infers it from the values
      # @param options [Hash] see {Base#initialize}
      # @raise [Versponse::DefinitionError] when values is empty, type is unknown or can't be inferred, or a value isn't of the type
      def initialize(values:, type: nil, **options)
        super(**options)
        raise DefinitionError, "#{key}: values must be a non-empty Array" unless values.is_a?(::Array) && !values.empty?

        @values = values.dup.freeze
        @type = type.nil? ? inferred_type : FieldType.resolve(type, key).first
        check_values!
      end

      # @param context [Versponse::SchemaContext, nil] schema generation context
      # @return [Hash] JSON Schema of the enum; nullable adds nil to the values, and "null" to type (or nullable: true
      #   in OpenAPI 3.0 documents, where a type union is an anyOf of single types)
      def schema(context)
        options = {"enum" => nullable? ? @values | [nil] : @values}.merge(schema_options)
        return FieldType.openapi30_union(@type, options, nullable: nullable?) if openapi30_union?(@type, context)

        nullable_type({"type" => @type}.merge(options), context)
      end

      # @param version [String] unused by scalars
      # @return [Versponse::Steps::Value] compiled step
      def step(version:)
        value_step
      end

      private

      # Like verquest's query coercion: one type per value class, number when integers and floats mix
      def inferred_type
        types = @values.compact.map do |value|
          json_type(value) || raise(DefinitionError, "#{key}: can't infer the enum type from #{value.inspect}, pass type:#{" (Symbols render as Symbols, use Strings)" if value.is_a?(::Symbol)}")
        end.uniq
        raise DefinitionError, "#{key}: can't infer the enum type from nil alone, pass type:" if types.empty?

        types.delete("integer") if types.include?("number")
        (types.size == 1) ? types.first : FieldType.union(types, key)
      end

      def json_type(value)
        case value
        when ::String then "string"
        when ::Integer then "integer"
        when ::Numeric then "number"
        when true, false then "boolean"
        when ::Hash then "object"
        end
      end

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
