# frozen_string_literal: true

module Versponse
  # Picks the plan of the first variant whose matchers === the value. Used for a single one_of
  # and for every item of a polymorphic collection.
  #
  # @api private
  class VariantDispatcher
    # @param variants [Array<Array(Array<#===>, #call)>] matchers and plan pairs
    # @param nullable [Boolean] render nil as nil instead of failing to match
    def initialize(variants, nullable:)
      @variants = variants.freeze
      @nullable = nullable
      freeze
    end

    # @param value [Object] value to render
    # @param context [Hash] serialize context
    # @return [Hash, nil] the value rendered by its variant
    # @raise [KeyError] when no variant matches (the plan wraps it in an ExtractionError)
    def call(value, context)
      return nil if value.nil? && @nullable

      plan_for(value).call(value, context)
    end

    private

    def plan_for(value)
      @variants.each { |matchers, plan| return plan if matchers.any? { |matcher| matcher === value } }
      raise KeyError, "no one_of variant matches #{value.class}"
    end
  end
end
