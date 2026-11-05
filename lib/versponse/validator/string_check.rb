# frozen_string_literal: true

module Versponse
  module Validator
    # minLength, maxLength and pattern
    #
    # @api private
    class StringCheck
      # @return [Array<String>] keywords this check owns
      def self.keywords = %w[minLength maxLength pattern]

      # @param schema [Hash] schema
      # @param compiler [Versponse::Validator::Compiler] resolves patterns like json_schemer
      # @return [StringCheck, nil] the check, nil without string keywords
      def self.build(schema, compiler)
        return unless keywords.any? { |keyword| schema.key?(keyword) }

        new(Range.new(schema["minLength"], schema["maxLength"]), schema["pattern"]&.then { |pattern| compiler.regexp(pattern) })
      end

      # @param lengths [Range] allowed lengths in characters
      # @param pattern [Regexp, nil] pattern matched anywhere in the string
      def initialize(lengths, pattern)
        @lengths = lengths
        @pattern = pattern
        freeze
      end

      # @param data [Object] value to check; anything but a String passes
      # @return [Boolean] true when the String matches
      def valid?(data)
        return true unless data.is_a?(String)

        @lengths.cover?(data.size) && (@pattern.nil? || @pattern.match?(data))
      end
    end
  end
end
