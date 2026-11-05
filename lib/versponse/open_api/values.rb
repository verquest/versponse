# frozen_string_literal: true

module Versponse
  module OpenAPI
    # Resolves declared values: blocks are called (with the version when they take an argument)
    # and Hash keys become Strings, never camelized
    #
    # @api private
    module Values
      # @param value [Object, Proc, nil] declared value or block
      # @param version [String] version being built
      # @return [Object, nil] the resolved, String-keyed value
      def self.resolve(value, version)
        value = value.arity.zero? ? value.call : value.call(version) if value.is_a?(Proc)
        stringify(value)
      end

      # @param value [Object] Hash, Array or scalar
      # @return [Object] the value with String Hash keys at every level
      def self.stringify(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, stringify(item)] }
        when Array then value.map { |item| stringify(item) }
        else value
        end
      end
    end
  end
end
