# frozen_string_literal: true

module Versponse
  module ContextOverride
    # Calls a callable with the parent object and context
    #
    # @api private
    class Call
      # @param callable [#call] normalized to (object, context)
      def initialize(callable)
        @callable = callable
        freeze
      end

      # @param object [Object] the object owning the property
      # @param context [Hash] parent context
      # @return [Hash] frozen child context
      # @raise [Versponse::ExtractionError] when the callable returns anything but a Hash (the plan adds the keys)
      def call(object, context)
        child = @callable.call(object, context)
        raise ExtractionError.new(label: "context", keys: [], detail: "context: must return a Hash, got #{child.class}") unless child.is_a?(Hash)

        child.frozen? ? child : child.dup.freeze
      end
    end
  end
end
