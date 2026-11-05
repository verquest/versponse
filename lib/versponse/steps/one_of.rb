# frozen_string_literal: true

module Versponse
  module Steps
    # Renders a value with the plan of the variant its dispatcher picks
    #
    # @api private
    class OneOf
      # @return [String] output key
      attr_reader :key

      # @param key [String] output key
      # @param extractor [#call] value reader
      # @param condition [Versponse::Condition, nil] if:/unless:
      # @param dispatcher [Versponse::VariantDispatcher] variant matching
      def initialize(key:, extractor:, condition:, dispatcher:)
        @key = key
        @extractor = extractor
        @condition = condition
        @dispatcher = dispatcher
        freeze
      end

      # @param object [Object] source
      # @param hash [Boolean] whether the source is a Hash
      # @param context [Hash] serialize context
      # @param output [Hash] Hash being built
      # @return [void]
      # @raise [KeyError] when no variant matches (the plan wraps it in an ExtractionError)
      def call(object, hash, context, output)
        return if @condition && !@condition.call(object, context)

        value = @extractor.call(object, hash, context)
        output[@key] = value.nil? ? nil : @dispatcher.call(value, context)
      end
    end
  end
end
