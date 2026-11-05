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
      # @param plan [Versponse::Plan, Versponse::LazyPlan] child plan
      # @param collection [Boolean] render each item
      def initialize(key:, extractor:, condition:, plan:, collection:)
        @key = key
        @extractor = extractor
        @condition = condition
        @plan = plan
        @collection = collection
        freeze
      end

      # @param object [Object] source
      # @param hash [Boolean] whether the source is a Hash
      # @param context [Hash] serialize context
      # @param output [Hash] Hash being built
      # @return [void]
      def call(object, hash, context, output)
        return if @condition && !@condition.call(object, context)

        value = @extractor.call(object, hash, context)
        output[@key] = if value.nil?
          nil
        elsif @collection
          value.to_ary.map { |item| @plan.call(item, context) }
        else
          @plan.call(value, context)
        end
      end
    end
  end
end
