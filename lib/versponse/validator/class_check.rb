# frozen_string_literal: true

module Versponse
  module Validator
    # A type check that is one class test (a schema allowing only number, string, array or object)
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
