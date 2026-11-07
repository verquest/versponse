# frozen_string_literal: true

module Versponse
  module Steps
    # A plain field with a formatter, applied to non-nil values
    #
    # @api private
    class ReadFormatted < Read
      # @param check [#valid?] checker of the property's schema
      # @param recheck [Boolean] check an unfrozen value again after the render
      # @return [CheckedReadFormatted] the same read, checking the formatted value it writes
      def checked(check, recheck:)
        CheckedReadFormatted.new(key: @key, name: @string, formatter: @formatter, check:, recheck:)
      end

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
