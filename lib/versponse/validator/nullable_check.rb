# frozen_string_literal: true

module Versponse
  module Validator
    # type: [X, "null"]: nil, or what the single-type check of X accepts
    #
    # @api private
    class NullableCheck
      # @param inner [#valid?] check of the other type
      def initialize(inner)
        @inner = inner
        freeze
      end

      # @param data [Object] value to check
      # @return [Boolean] true when data is nil or passes the inner check
      def valid?(data)
        data.nil? || @inner.valid?(data)
      end
    end
  end
end
