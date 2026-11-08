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
      # @param recheck [Boolean] a change in place can break the schema, so a value not frozen all the way down is
      #   checked after the render (see InlineValidation.check)
      def initialize(key:, name:, formatter:, check:, recheck:)
        @check = check
        @recheck = recheck
        super(key:, name:, formatter:)
      end

      # The check is written out here, in CheckedReadFormatted and in CheckedValue, rather than calling
      # InlineValidation.check: the extra call costs about 25 ns per field under YJIT
      #
      # @param object [Object] source
      # @param hash [Boolean] whether the source is a Hash
      # @param _context [Hash] unused
      # @param output [Hash] Hash being built
      # @param _expansion [Versponse::Expansion] unused
      # @return [void]
      def call(object, hash, _context, output, _expansion)
        value = output[@key] = hash ? object.fetch(@symbol) { object.fetch(@string) } : object.public_send(@symbol)
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
