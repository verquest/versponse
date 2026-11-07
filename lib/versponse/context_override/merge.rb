# frozen_string_literal: true

module Versponse
  module ContextOverride
    # Merges a frozen Hash over the parent context
    #
    # @api private
    class Merge
      # @param hash [Hash] deep-frozen values to merge
      def initialize(hash)
        @hash = hash
        freeze
      end

      # @param _object [Object] unused
      # @param context [Hash] parent context
      # @return [Hash] frozen child context; the built Hash itself over an empty context
      def call(_object, context)
        context.empty? ? @hash : context.merge(@hash).freeze
      end
    end
  end
end
