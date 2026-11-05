# frozen_string_literal: true

module Versponse
  module Validator
    # The checker of a boolean schema, or of a schema without assertions
    #
    # @api private
    class Constant
      # @param result [Boolean] the result of every check
      def initialize(result)
        @result = result
        freeze
      end

      # @param _data [Object] ignored
      # @return [Boolean] the constant result
      def valid?(_data)
        @result
      end

      # Accepts anything
      VALID = new(true)
      # Rejects anything
      INVALID = new(false)

      # @param result [Boolean] schema true or false
      # @return [Constant] VALID or INVALID
      def self.for(result)
        result ? VALID : INVALID
      end
    end
  end
end
