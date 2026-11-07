# frozen_string_literal: true

module Versponse
  module Validator
    # type, with json_schemer's semantics (integer accepts 1.0, number includes NaN)
    #
    # @api private
    class TypeCheck
      # Type tests, matching json_schemer's valid_type
      TESTS = {
        "null" => :nil?.to_proc,
        "boolean" => ->(data) { data == true || data == false },
        "number" => ->(data) { data.is_a?(Numeric) },
        "integer" => ->(data) { JSONSchemer::Draft202012::Vocab::Validation::Type.valid_integer?(data) },
        "string" => ->(data) { data.is_a?(String) },
        "array" => ->(data) { data.is_a?(Array) },
        "object" => ->(data) { data.is_a?(Hash) }
      }.freeze

      # Types that are a class test, checked without a lambda when a schema allows only that type
      CLASSES = {"number" => Numeric, "string" => String, "array" => Array, "object" => Hash}.freeze

      # Draft 4 and OpenAPI 3.0 (based on it) accept only Integers; later versions also accept 1.0
      INTEGER_ONLY = %i[draft4 openapi30].freeze

      # JSON Schema versions where nullable: true adds "null" to type (json_schemer's OpenAPI30::Vocab::Base::Type)
      NULLABLE_TYPE = %i[openapi30].freeze

      # Integer test of draft 4 and OpenAPI 3.0
      STRICT_INTEGER = ->(data) { data.is_a?(Integer) }

      # @return [Array<String>] keywords this check owns
      def self.keywords = %w[type]

      # Reads config.json_schema_version; checkers are cached per class, and setting it resets them
      #
      # @param schema [Hash] schema
      # @param _compiler [Versponse::Validator::Compiler] unused
      # @return [TypeCheck, nil] the check, nil without type
      # @raise [Versponse::Validator::Compiler::Unsupported] for an unknown type
      def self.build(schema, _compiler)
        return unless schema.key?("type")

        types = Array(schema["type"])
        types = (types + ["null"]).uniq if schema["nullable"] == true && NULLABLE_TYPE.include?(Versponse.configuration.json_schema_version)
        single = types.map { |type| single(type) }
        return single.first if types.one? && single.first
        return NullableCheck.new(single[types.index { |type| type != "null" }]) if types.size == 2 && types.include?("null") && single.compact.one?

        new(types.map { |type| test_for(type) })
      end

      # @param type [String] one JSON Schema type
      # @return [#valid?, nil] a check of only that type, nil for null and unknown types
      def self.single(type)
        return ClassCheck.new(CLASSES.fetch(type)) if CLASSES.key?(type)
        return BooleanCheck.new if type == "boolean"
        return unless type == "integer"

        INTEGER_ONLY.include?(Versponse.configuration.json_schema_version) ? ClassCheck.new(Integer) : IntegerCheck.new
      end
      private_class_method :single

      def self.test_for(type)
        return STRICT_INTEGER if type == "integer" && INTEGER_ONLY.include?(Versponse.configuration.json_schema_version)

        TESTS.fetch(type) { raise Compiler::Unsupported, "type #{type}" }
      end
      private_class_method :test_for

      # @param tests [Array<Proc>] tests of the allowed types
      def initialize(tests)
        @tests = tests.freeze
        freeze
      end

      # @param data [Object] value to check
      # @return [Boolean] true when data has one of the types
      def valid?(data)
        @tests.any? { |test| test.call(data) }
      end
    end
  end
end
