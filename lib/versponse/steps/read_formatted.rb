# frozen_string_literal: true

module Versponse
  module Steps
    # A plain field with a formatter, applied to non-nil values
    #
    # @api private
    class ReadFormatted < Read
      # @param object [Object] source
      # @param hash [Boolean] whether the source is a Hash
      # @param _context [Hash] unused
      # @param output [Hash] Hash being built
      # @param _expansion [Versponse::Expansion] unused
      # @return [void]
      def call(object, hash, _context, output, _expansion)
        value = hash ? object.fetch(@symbol) { object.fetch(@string) } : object.public_send(@symbol)
        output[@key] = value.nil? ? nil : @formatter.call(value)
      end
    end
  end
end
