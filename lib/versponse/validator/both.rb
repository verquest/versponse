# frozen_string_literal: true

module Versponse
  module Validator
    # Two checkers, called without an Array loop (the common case: a type and one other check)
    #
    # @api private
    class Both
      # @param first [#valid?] first checker
      # @param second [#valid?] second checker
      def initialize(first, second)
        @first = first
        @second = second
        freeze
      end

      # @param data [Object] value to check
      # @return [Boolean] true when both checkers accept data
      def valid?(data)
        @first.valid?(data) && @second.valid?(data)
      end
    end
  end
end
