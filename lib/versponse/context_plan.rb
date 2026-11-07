# frozen_string_literal: true

module Versponse
  # A one_of variant's plan rendered with the variant's context: (called with the matched value)
  #
  # @api private
  class ContextPlan
    # @param plan [#call] the variant's plan (full or collapsed)
    # @param override [#call] the variant's context override
    def initialize(plan, override)
      @plan = plan
      @override = override
      freeze
    end

    # @param object [Object] the matched value
    # @param context [Hash] context of the one_of
    # @param expansion [Versponse::Expansion] expand tree node
    # @return [Hash] rendered object
    def call(object, context, expansion = Expansion::NONE)
      @plan.call(object, @override.call(object, context), expansion)
    end
  end
end
