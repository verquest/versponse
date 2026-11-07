# frozen_string_literal: true

module Versponse
  # Handle to another class's plan, compiled on first use so cyclic references are safe
  #
  # @api private
  class LazyPlan
    # @param klass [Class] Versponse response class
    # @param version [String] requested version name
    # @param view [Symbol] view name
    def initialize(klass, version:, view:)
      @klass = klass
      @version = version
      @view = view
    end

    # @param object [Object] source
    # @param context [Hash] serialize context
    # @param expansion [Versponse::Expansion] expand tree node
    # @return [Hash] rendered object
    def call(object, context, expansion = Expansion::NONE)
      (@plan ||= resolve).call(object, context, expansion)
    end

    # @return [Versponse::Plan] the compiled plan this handle renders with
    def resolve
      @klass.versponse.plan(version: @version, view: @view)
    end
  end
end
