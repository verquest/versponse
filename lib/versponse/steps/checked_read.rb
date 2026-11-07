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
      # @param recheck [Boolean] the schema may accept an Array or Hash, so an unfrozen value is checked again after
      #   the render (see InlineValidation.recheck_later)
      def initialize(key:, name:, formatter:, check:, recheck:)
        @check = check
        @recheck = recheck
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
        # The rescue covers the check only: a check that raises, or defers (UncaughtThrowError outside Root), fails
        ok = begin
          @check.valid?(value)
        rescue
          false
        end
        if !ok
          InlineValidation.failed!
        elsif @recheck && !value.frozen?
          InlineValidation.recheck_later(@check, value)
        end
      end
    end
  end
end
