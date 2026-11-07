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
      # @param context_override [#call, nil] computes the variants' context from (object, context)
      def initialize(key:, extractor:, condition:, dispatcher:, collapsed_dispatcher: nil, context_override: nil)
        @key = key
        @extractor = extractor
        @condition = condition
        @dispatcher = dispatcher
        @collapsed_dispatcher = collapsed_dispatcher
        @context_override = context_override
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
      # @param expansion [Versponse::Expansion] expand tree node of the parent
      # @return [void]
      # @raise [KeyError] when no variant matches (the plan wraps it in an ExtractionError)
      def call(object, hash, context, output, expansion)
        return if @condition && !@condition.call(object, context)

        value = @extractor.call(object, hash, context)
        return output[@key] = nil if value.nil?

        context = @context_override.call(object, context) if @context_override
        dispatcher = (@collapsed_dispatcher && !expansion.expand?(@key)) ? @collapsed_dispatcher : @dispatcher
        output[@key] = dispatch(dispatcher, value, context, expansion.child(@key))
      end

      private

      # Errors from the variant plans (and a value matching no variant) are marked like a nested step's
      def dispatch(dispatcher, value, context, node)
        dispatcher.call(value, context, node)
      rescue => e
        ErrorPolicy.mark_nested!(e)
        raise
      end
    end
  end
end
