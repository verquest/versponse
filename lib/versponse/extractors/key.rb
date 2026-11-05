# frozen_string_literal: true

module Versponse
  module Extractors
    # Reads a method, or a Symbol then String key of a Hash
    #
    # @api private
    class Key
      # @param name [String, Symbol] method or key name
      def initialize(name)
        @symbol = name.to_sym
        @string = name.to_s.freeze
        freeze
      end

      # @param object [Object] source
      # @param hash [Boolean] whether the source is a Hash
      # @param _context [Hash] unused
      # @return [Object] the value
      # @raise [KeyError] when a Hash has neither key
      def call(object, hash, _context)
        return object.public_send(@symbol) unless hash

        object.fetch(@symbol) { object.fetch(@string) }
      end
    end
  end
end
