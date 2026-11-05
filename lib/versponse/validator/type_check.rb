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

      # @return [Array<String>] keywords this check owns
      def self.keywords = %w[type]

      # @param schema [Hash] schema
      # @param _compiler [Versponse::Validator::Compiler] unused
      # @return [TypeCheck, nil] the check, nil without type
      # @raise [Versponse::Validator::Compiler::Unsupported] for an unknown type
      def self.build(schema, _compiler)
        return unless schema.key?("type")

        new(Array(schema["type"]).map { |type| TESTS.fetch(type) { raise Compiler::Unsupported, "type #{type}" } })
      end

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
