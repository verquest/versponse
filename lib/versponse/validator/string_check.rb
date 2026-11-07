# frozen_string_literal: true

module Versponse
  module Validator
    # minLength, maxLength and pattern
    #
    # @api private
    class StringCheck
      # @return [Array<String>] keywords this check owns
      def self.keywords = %w[minLength maxLength pattern]

      # @return [Class] the class a type folded into this check requires
      def self.shape = String

      # @param schema [Hash] schema
      # @param compiler [Versponse::Validator::Compiler] resolves patterns like json_schemer
      # @return [StringCheck, nil] the check, nil without string keywords
      def self.build(schema, compiler)
        return unless keywords.any? { |keyword| schema.key?(keyword) }

        new(Range.new(schema["minLength"], schema["maxLength"]), schema["pattern"]&.then { |pattern| compiler.regexp(pattern) })
      end

      # @param lengths [Range] allowed lengths in characters
      # @param pattern [Regexp, nil] pattern matched anywhere in the string
      # @param strict [Boolean] true when anything but a String fails (type: "string" folded in)
      def initialize(lengths, pattern, strict: false)
        @lengths = lengths
        @pattern = pattern
        @strict = strict
        freeze
      end

      # @return [StringCheck] the same check, failing anything but a String
      def strict
        self.class.new(@lengths, @pattern, strict: true)
      end

      # @param data [Object] value to check; anything but a String passes unless strict
      # @return [Boolean] true when the String matches
      def valid?(data)
        return !@strict unless data.is_a?(String)

        @lengths.cover?(data.size) && (@pattern.nil? || @pattern.match?(data))
      end
    end
  end
end
