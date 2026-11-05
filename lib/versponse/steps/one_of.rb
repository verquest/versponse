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
      # @param collapsed_dispatcher [Versponse::VariantDispatcher, nil] matching to collapsed variants (expandable one_of)
      def initialize(key:, extractor:, condition:, dispatcher:, collapsed_dispatcher: nil)
        @key = key
        @extractor = extractor
        @condition = condition
        @dispatcher = dispatcher
        @collapsed_dispatcher = collapsed_dispatcher
        freeze
      end

      # @param object [Object] source
      # @param hash [Boolean] whether the source is a Hash
      # @param context [Hash] serialize context
      # @param output [Hash] Hash being built
      # @param expansion [Versponse::Expansion] expand tree node of the parent
      # @return [void]
      # @raise [KeyError] when no variant matches (the plan wraps it in an ExtractionError)
      def call(object, hash, context, output, expansion)
        return if @condition && !@condition.call(object, context)

        value = @extractor.call(object, hash, context)
        return output[@key] = nil if value.nil?

        dispatcher = (@collapsed_dispatcher && !expansion.expand?(@key)) ? @collapsed_dispatcher : @dispatcher
        output[@key] = dispatcher.call(value, context, expansion.child(@key))
      end
    end
  end
end
