# frozen_string_literal: true

module Versponse
  module Steps
    # A plain read that checks the value it writes
    #
    # @api private
    class CheckedRead < Read
      # @param key [String] output key
      # @param name [String, Symbol] method or Hash key to read
      # @param formatter [#call, nil] formatter (used by CheckedReadFormatted)
      # @param check [#valid?] checker of the property's schema
      def initialize(key:, name:, formatter:, check:)
        @check = check
        super(key:, name:, formatter:)
      end

      # @param object [Object] source
      # @param hash [Boolean] whether the source is a Hash
      # @param _context [Hash] unused
      # @param output [Hash] Hash being built
      # @param _expansion [Versponse::Expansion] unused
      # @return [void]
      def call(object, hash, _context, output, _expansion)
        value = output[@key] = hash ? object.fetch(@symbol) { object.fetch(@string) } : object.public_send(@symbol)
        # The rescue covers the check only (a raising or deferring check is a failure); see InlineValidation.ok?
        ok = begin
          @check.valid?(value)
        rescue
          false
        end
        InlineValidation.failed! unless ok
      end
    end
  end
end
