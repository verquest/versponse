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
        return ClassCheck.new(CLASSES.fetch(types.first)) if types.one? && CLASSES.key?(types.first)

        new(types.map { |type| test_for(type) })
      end

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

    # A type check that is one class test (a schema allowing only number, string, array or object)
    #
    # @api private
    class ClassCheck
      # @param klass [Class] the class data must be
      def initialize(klass)
        @klass = klass
        freeze
      end

      # @param data [Object] value to check
      # @return [Boolean] true when data is of the class
      def valid?(data)
        data.is_a?(@klass)
      end
    end
  end
end
