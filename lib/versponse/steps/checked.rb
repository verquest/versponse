# frozen_string_literal: true

module Versponse
  module Steps
    # Any step whose written value is checked afterwards (nested values, one_of); checks only when the step wrote
    # its key, which is sound because validating plans have unique keys
    #
    # @api private
    class Checked
      # @return [String] output key
      attr_reader :key

      # @param step [#call] wrapped step
      # @param check [#valid?] checker of the written value
      def initialize(step, check)
        @step = step
        @key = step.key
        @check = check
        freeze
      end

      # @return [Boolean] true when the wrapped step has if:/unless:
      def conditional?
        @step.conditional?
      end

      # @param object [Object] source
      # @param hash [Boolean] whether the source is a Hash
      # @param context [Hash] serialize context
      # @param output [Hash] Hash being built
      # @param expansion [Versponse::Expansion] expand tree node of the parent
      # @return [void]
      def call(object, hash, context, output, expansion)
        @step.call(object, hash, context, output, expansion)
        return unless output.key?(@key)

        # The rescue covers the check only: a check that raises, or defers (UncaughtThrowError outside Root), fails
        ok = begin
          @check.valid?(output[@key])
        rescue
          false
        end
        InlineValidation.failed! unless ok
      end
    end
  end
end
