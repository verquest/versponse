# frozen_string_literal: true

module Versponse
  module Validator
    # json_schemer reads Symbol keys as their Strings, so the object checks do too: a Hash with Symbol keys is
    # checked again with String keys
    #
    # @api private
    module StringKeys
      # @param data [Hash] value being checked
      # @return [Hash{String => Object}, nil] the Hash with String keys, nil when a key is neither a String nor a
      #   Symbol, or a Symbol and a String name the same key (json_schemer decides those)
      def self.call(data)
        return unless data.each_key.all? { |key| key.is_a?(String) || key.is_a?(Symbol) }

        strings = data.transform_keys(&:to_s)
        strings if strings.size == data.size
      end
    end
  end
end
