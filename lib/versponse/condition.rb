# frozen_string_literal: true

module Versponse
  # Compiled if:/unless: pair, called with (object, context)
  #
  # @api private
  class Condition
    # @param if_callable [Proc, nil] emit the key only when this returns truthy
    # @param unless_callable [Proc, nil] emit the key only when this returns falsy
    # @return [Condition, nil] nil when neither is given
    def self.build(if_callable, unless_callable)
      return if if_callable.nil? && unless_callable.nil?

      new(Callable.normalize(if_callable), Callable.normalize(unless_callable))
    end

    # @param if_callable [Proc, nil] normalized if: callable
    # @param unless_callable [Proc, nil] normalized unless: callable
    def initialize(if_callable, unless_callable)
      @if_callable = if_callable
      @unless_callable = unless_callable
      freeze
    end

    # @param object [Object] serialized object
    # @param context [Hash] serialize context
    # @return [Boolean] whether the key is emitted
    def call(object, context)
      (@if_callable.nil? || @if_callable.call(object, context)) &&
        (@unless_callable.nil? || !@unless_callable.call(object, context))
    end
  end
end
