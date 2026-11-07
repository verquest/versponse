# frozen_string_literal: true

module Versponse
  module Validator
    # type: boolean, compared with == as json_schemer does
    #
    # @api private
    class BooleanCheck
      # @param data [Object] value to check
      # @return [Boolean] true when data is true or false
      def valid?(data)
        data == true || data == false
      end
    end
  end
end
