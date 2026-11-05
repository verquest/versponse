# frozen_string_literal: true

module Versponse
  # Collapsed one_of variant: the discriminator const followed by the class's identifier
  #
  # @api private
  class DiscriminatedPlan
    # @param plan [#call] the variant class's collapsed plan
    # @param key [String] discriminator property
    # @param value [Object] the variant's discriminator value
    def initialize(plan, key:, value:)
      @plan = plan
      @key = key
      @value = value
      freeze
    end

    # @param object [Object] source
    # @param context [Hash] serialize context
    # @param expansion [Versponse::Expansion] expand tree node
    # @return [Hash] discriminator and identifier
    def call(object, context, expansion = Expansion::NONE)
      {@key => @value}.merge!(@plan.call(object, context, expansion))
    end
  end
end
