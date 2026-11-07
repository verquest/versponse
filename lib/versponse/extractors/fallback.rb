# frozen_string_literal: true

module Versponse
  module Extractors
    # Reads with another extractor and falls back to a callable when the value is nil (default:, on_nil)
    #
    # @api private
    class Fallback
      # @param extractor [#call] value reader
      # @param fallback [#call] called with (object, context) for a nil value
      def initialize(extractor, fallback)
        @extractor = extractor
        @fallback = fallback
        freeze
      end

      # @param object [Object] source
      # @param hash [Boolean] whether the source is a Hash
      # @param context [Hash] serialize context
      # @return [Object] the value, or the fallback's for nil
      def call(object, hash, context)
        value = @extractor.call(object, hash, context)
        value.nil? ? @fallback.call(object, context) : value
      end
    end
  end
end
