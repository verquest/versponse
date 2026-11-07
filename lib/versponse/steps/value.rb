# frozen_string_literal: true

module Versponse
  # Compiled operations a plan runs for each property
  module Steps
    # Writes one extracted value, formatted when a formatter is bound
    #
    # @api private
    class Value
      # @return [String] output key
      attr_reader :key

      # @param key [String] output key
      # @param extractor [#call] value reader
      # @param condition [Versponse::Condition, nil] if:/unless:
      # @param formatter [#call, nil] applied to non-nil values
      def initialize(key:, extractor:, condition:, formatter:)
        @key = key
        @extractor = extractor
        @condition = condition
        @formatter = formatter
        freeze
      end

      # @return [Boolean] true with if:/unless:
      def conditional?
        !@condition.nil?
      end

      # @param object [Object] source
      # @param hash [Boolean] whether the source is a Hash
      # @param context [Hash] serialize context
      # @param output [Hash] Hash being built
      # @param _expansion [Versponse::Expansion] unused
      # @return [void]
      def call(object, hash, context, output, _expansion)
        return if @condition && !@condition.call(object, context)

        value = @extractor.call(object, hash, context)
        value = @formatter.call(value) if @formatter && !value.nil?
        output[@key] = value
      end
    end
  end
end
