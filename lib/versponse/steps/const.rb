# frozen_string_literal: true

module Versponse
  module Steps
    # Writes a constant value
    #
    # @api private
    class Const
      # @return [String] output key
      attr_reader :key

      # @param key [String] output key
      # @param value [Object] constant value
      # @param condition [Versponse::Condition, nil] if:/unless:
      def initialize(key:, value:, condition:)
        @key = key
        @value = value
        @condition = condition
        freeze
      end

      # @param object [Object] source
      # @param _hash [Boolean] unused
      # @param context [Hash] serialize context
      # @param output [Hash] Hash being built
      # @param _expansion [Versponse::Expansion] unused
      # @return [void]
      def call(object, _hash, context, output, _expansion)
        return if @condition && !@condition.call(object, context)

        output[@key] = @value
      end
    end
  end
end
