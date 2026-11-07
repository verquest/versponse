# frozen_string_literal: true

module Versponse
  module Validator
    # type: integer from JSON Schema 6 on: json_schemer's own test, so 1.0 passes and NaN raises (Root then defers)
    #
    # @api private
    class IntegerCheck
      # @param data [Object] value to check
      # @return [Boolean] true when data is an integer
      def valid?(data)
        JSONSchemer::Draft202012::Vocab::Validation::Type.valid_integer?(data)
      end
    end
  end
end
