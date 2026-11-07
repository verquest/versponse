# frozen_string_literal: true

module Versponse
  module Steps
    # Renders a nested object, or each item of a collection, with a child plan
    #
    # @api private
    class Nested
      # @return [String] output key
      attr_reader :key

      # @param key [String] output key
      # @param extractor [#call] value reader
      # @param condition [Versponse::Condition, nil] if:/unless:
      # @param plan [#call] child plan
      # @param collection [Boolean] render each item
      # @param collapsed_plan [#call, nil] plan used when the association is expandable and not expanded
      # @param collapse_if [#call, nil] the referenced identifier's condition; when it is false for the value
      #   (for a collection: for any item) the full plan is used instead of collapsed_plan
      # @param nil_fails [Boolean] in a validating plan, a nil value fails its schema (see InlineValidation)
      def initialize(key:, extractor:, condition:, plan:, collection:, collapsed_plan: nil, collapse_if: nil, nil_fails: false)
        @key = key
        @extractor = extractor
        @condition = condition
        @plan = plan
        @collection = collection
        @collapsed_plan = collapsed_plan
        @collapse_if = collapse_if
        @nil_fails = nil_fails
        freeze
      end

      # @return [Boolean] true with if:/unless:
      def conditional?
        !@condition.nil?
      end

      # @return [Boolean] true when each item of a collection is rendered
      def collection?
        @collection
      end

      # @return [Array<#call>] the child plan, and the collapsed plan when there is one
      def plans
        [@plan, @collapsed_plan].compact
      end

      # @param plan [#call] child plan
      # @param collapsed_plan [#call, nil] plan used when collapsed
      # @param nil_fails [Boolean] a nil value fails validation (validating plans only)
      # @return [Nested] the same step rendering with these plans
      def with_plans(plan:, collapsed_plan:, nil_fails: false)
        self.class.new(key: @key, extractor: @extractor, condition: @condition, plan:, collection: @collection,
          collapsed_plan:, collapse_if: @collapse_if, nil_fails:)
      end

      # @param object [Object] source
      # @param hash [Boolean] whether the source is a Hash
      # @param context [Hash] serialize context
      # @param output [Hash] Hash being built
      # @param expansion [Versponse::Expansion] expand tree node of the parent
      # @return [void]
      # @raise [Versponse::ExtractionError] with the item index in its keys when a collection item fails
      def call(object, hash, context, output, expansion)
        return if @condition && !@condition.call(object, context)

        value = @extractor.call(object, hash, context)
        output[@key] = if value.nil?
          InlineValidation.failed! if @nil_fails
          nil
        else
          collapse = @collapsed_plan && !expansion.expand?(@key) && (@collapse_if.nil? || collapse?(value, context))
          plan = collapse ? @collapsed_plan : @plan
          node = expansion.child(@key)
          @collection ? Collections.map(Collections.items(value)) { |item| plan.call(item, context, node) } : plan.call(value, context, node)
        end
      end

      private

      # A collection collapses only when every item passes, so its items share one shape
      def collapse?(value, context)
        return @collapse_if.call(value, context) unless @collection

        Collections.items(value).all? { |item| @collapse_if.call(item, context) }
      end
    end
  end
end
