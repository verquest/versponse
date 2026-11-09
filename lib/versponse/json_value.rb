# frozen_string_literal: true

module Versponse
  # Values with a JSON type, which a const renders as written. Numbers are accepted as enum accepts them (any real,
  # finite Numeric); Hash keys may be Symbols, which JSON generators and output validation read as Strings.
  #
  # @api private
  module JSONValue
    # @param value [Object] value
    # @return [Boolean] true for nil, true, false, Strings, real finite numbers, and Arrays and Hashes (with String
    #   or Symbol keys) of them
    def self.json?(value)
      case value
      when nil, true, false, ::String then true
      when ::Numeric then value.real? && value.finite?
      when ::Array then value.all? { |item| json?(item) }
      when ::Hash then value.all? { |key, item| (key.is_a?(::String) || key.is_a?(::Symbol)) && json?(item) }
      else false
      end
    end
  end
end
