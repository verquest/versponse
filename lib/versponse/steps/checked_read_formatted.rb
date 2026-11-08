# frozen_string_literal: true

module Versponse
  module Steps
    # A formatted read that checks the formatted value it writes
    #
    # @api private
    class CheckedReadFormatted < CheckedRead
      # @param object [Object] source
      # @param hash [Boolean] whether the source is a Hash
      # @param _context [Hash] unused
      # @param output [Hash] Hash being built
      # @param _expansion [Versponse::Expansion] unused
      # @return [void]
      def call(object, hash, _context, output, _expansion)
        value = hash ? object.fetch(@symbol) { object.fetch(@string) } : object.public_send(@symbol)
        value = output[@key] = value.nil? ? nil : @formatter.call(value)
        if @recheck && !Ractor.shareable?(value)
          InlineValidation.recheck_later(@check, value)
        else
          # The rescue covers the check only: a check that raises, or defers (UncaughtThrowError outside Root), fails
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
end
