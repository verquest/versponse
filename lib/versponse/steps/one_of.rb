# frozen_string_literal: true

module Versponse
  module Steps
    # Renders a value with the plan of the first variant whose matcher === the value
    #
    # @api private
    class OneOf
      # @return [String] output key
      attr_reader :key

      # @param key [String] output key
      # @param extractor [#call] value reader
      # @param condition [Versponse::Condition, nil] if:/unless:
      # @param variants [Array<Array(Array<#===>, Versponse::LazyPlan)>] matchers and plan pairs
      def initialize(key:, extractor:, condition:, variants:)
        @key = key
        @extractor = extractor
        @condition = condition
        @variants = variants
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
        output[@key] = value.nil? ? nil : plan_for(value).call(value, context)
      end

      private

      def plan_for(value)
        @variants.each { |matchers, plan| return plan if matchers.any? { |matcher| matcher === value } }
        raise KeyError, "no one_of variant matches #{value.class}"
      end
    end
  end
end
