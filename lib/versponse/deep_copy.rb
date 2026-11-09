# frozen_string_literal: true

module Versponse
  # Unfrozen deep copy of a value handed to a caller who may change it
  #
  # @api private
  module DeepCopy
    # @param value [Object] value, usually frozen
    # @return [Object] a copy whose Hashes, Arrays and Strings are new, unfrozen objects; other values as they are
    def self.call(value)
      case value
      when ::Hash then value.to_h { |key, item| [key, call(item)] }
      when ::Array then value.map { |item| call(item) }
      when ::String then value.dup
      else value
      end
    end

    # Scalars render as they are; copying them on every render would only cost
    #
    # @param value [Object] value
    # @return [Boolean] true for a Hash or Array, which renders as a copy
    def self.container?(value)
      value.is_a?(::Hash) || value.is_a?(::Array)
    end
  end
end
