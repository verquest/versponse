# frozen_string_literal: true

module Versponse
  module Extractors
    # Calls a value block with (object, context)
    #
    # @api private
    class Block
      # @param block [Proc] value block
      def initialize(block)
        @block = block
        freeze
      end

      # @param object [Object] source
      # @param _hash [Boolean] unused
      # @param context [Hash] serialize context
      # @return [Object] the block's result
      def call(object, _hash, context)
        @block.call(object, context)
      end
    end
  end
end
