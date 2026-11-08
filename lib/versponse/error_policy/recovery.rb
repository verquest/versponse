# frozen_string_literal: true

module Versponse
  module ErrorPolicy
    # Applies one property's policy when its step fails, then reports the error
    #
    # @api private
    class Recovery
      # @param policy [Symbol, #call] :nullify, :omit or a handler
      # @param key [String] the property's key
      # @param response [Class, nil] the class whose plan holds the property
      # @param explicit [Boolean] declared on the property itself, so it also recovers nested failures
      def initialize(policy, key:, response:, explicit:)
        @policy = policy
        @key = key
        @response = response
        @explicit = explicit
        @errors = Versponse.configuration.recoverable_errors
        freeze
      end

      # A failure from a child plan is recovered only by an explicit policy (an ExtractionError then too). Other
      # Versponse errors, and errors raised by the on_recovered_error hook, are never recovered.
      #
      # @param error [StandardError] what the step raised
      # @return [Boolean] true when this policy handles it
      def recovers?(error)
        return false if ErrorPolicy.unrecoverable?(error)
        return @explicit && (error.is_a?(ExtractionError) || (!error.is_a?(Error) && recoverable?(error))) if ErrorPolicy.nested?(error)

        !error.is_a?(Error) && recoverable?(error)
      end

      # Writes nil, leaves the key out, or writes the handler's value. Each skips the step's inline check, so it
      # forces full output validation (a nullable property's declared any_of may still reject nil, a left-out key may
      # be required).
      #
      # @param error [StandardError] what the step raised
      # @param object [Object] the object being rendered
      # @param context [Hash] serialize context
      # @param output [Hash] Hash being built
      # @return [void]
      def recover(error, object, context, output)
        if @policy == :omit
          output.delete(@key)
        else
          output[@key] = (@policy == :nullify) ? nil : @policy.call(error, object, @key, context)
        end
        InlineValidation.failed!
        report(error, object)
      end

      private

      # A hook error is marked, so a parent's policy doesn't recover it either
      def report(error, object)
        Versponse.configuration.on_recovered_error&.call(error, response: @response, key: @key, object:)
      rescue => e
        ErrorPolicy.mark_unrecoverable!(e)
        raise
      end

      def recoverable?(error)
        @errors.any? { |klass| error.is_a?(klass) }
      end
    end
  end
end
