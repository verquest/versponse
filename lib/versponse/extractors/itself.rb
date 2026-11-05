# frozen_string_literal: true

module Versponse
  module Extractors
    # Returns the source object (map: ".")
    #
    # @api private
    class Itself
      # Shared instance
      INSTANCE = new.freeze

      # @param object [Object] source
      # @param _hash [Boolean] unused
      # @param _context [Hash] unused
      # @return [Object] the source object
      def call(object, _hash, _context)
        object
      end
    end
  end
end
