# frozen_string_literal: true

module Versponse
  module Steps
    # A value step that checks the value it writes
    #
    # @api private
    class CheckedValue < Value
      # @param key [String] output key
      # @param extractor [#call] value reader
      # @param condition [Versponse::Condition, nil] if:/unless:
      # @param formatter [#call, nil] applied to non-nil values
      # @param check [#valid?] checker of the property's schema
      def initialize(key:, extractor:, condition:, formatter:, check:)
        @check = check
        super(key:, extractor:, condition:, formatter:)
      end

      # @param object [Object] source
      # @param hash [Boolean] whether the source is a Hash
      # @param context [Hash] serialize context
      # @param output [Hash] Hash being built
      # @param _expansion [Versponse::Expansion] unused
      # @return [void]
      def call(object, hash, context, output, _expansion)
        return if @condition && !@condition.call(object, context)

        value = @extractor.call(object, hash, context)
        value = @formatter.call(value) if @formatter && !value.nil?
        output[@key] = value
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
