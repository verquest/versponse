# frozen_string_literal: true

module Versponse
  # Deeply frozen copy of a schema. Copies instead of freezing in place, so schemas returned by
  # other gems (verquest's internal hashes) are never frozen behind their back.
  #
  # @api private
  module DeepFreeze
    # @param value [Object] Hash, Array, String or another value
    # @return [Object] a frozen copy
    def self.call(value)
      case value
      when Hash then value.to_h { |key, item| [call(key), call(item)] }.freeze
      when Array then value.map { |item| call(item) }.freeze
      when String then value.frozen? ? value : value.dup.freeze
      else value
      end
    end
  end
end
