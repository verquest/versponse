# frozen_string_literal: true

module Versponse
  module Validator
    # A type check that is one class test (only number, string, array, object, or integer where only Integers count)
    #
    # @api private
    class ClassCheck
      # @param klass [Class] the class data must be
      def initialize(klass)
        @klass = klass
        freeze
      end

      # @param data [Object] value to check
      # @return [Boolean] true when data is of the class
      def valid?(data)
        data.is_a?(@klass)
      end
    end
  end
end
