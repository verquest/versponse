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
      # @raise [Versponse::ExtractionError] with the item index in its keys when a collection item fails
      def call(object, hash, context, output)
        return if @condition && !@condition.call(object, context)

        value = @extractor.call(object, hash, context)
        output[@key] = if value.nil?
          nil
        elsif @collection
          render_items(value.to_ary, context)
        else
          @plan.call(value, context)
        end
      end

      private

      def render_items(items, context)
        index = 0
        items.map do |item|
          rendered = @plan.call(item, context)
          index += 1
          rendered
        end
      rescue ExtractionError => e
        raise ExtractionError.new(label: e.label, keys: [index.to_s, *e.keys], detail: e.detail)
      rescue NoMethodError, KeyError => e
        raise ExtractionError.new(label: "", keys: [index.to_s], detail: e.message)
      end
    end
  end
end
