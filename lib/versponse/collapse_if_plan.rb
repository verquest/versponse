# frozen_string_literal: true

module Versponse
  # Collapsed one_of variant whose class declares collapse_if: renders the full plan when the condition is false
  #
  # @api private
  class CollapseIfPlan
    # @param condition [#call] collapse_if, called with (object, context)
    # @param collapsed [#call] the variant's collapsed plan
    # @param full [#call] the variant's full plan
    def initialize(condition, collapsed:, full:)
      @condition = condition
      @collapsed = collapsed
      @full = full
      freeze
    end

    # @param object [Object] source
    # @param context [Hash] serialize context
    # @param expansion [Versponse::Expansion] expand tree node
    # @return [Hash] the collapsed form, or the full form when the condition is false
    def call(object, context, expansion = Expansion::NONE)
      (@condition.call(object, context) ? @collapsed : @full).call(object, context, expansion)
    end
  end
end
