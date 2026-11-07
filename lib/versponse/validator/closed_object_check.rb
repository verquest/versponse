# frozen_string_literal: true

module Versponse
  module Validator
    # An object with additionalProperties: false whose required keys are all declared properties: each declared key
    # is fetched and checked, and a count of the present ones equal to the Hash size proves there are no others
    #
    # @api private
    class ClosedObjectCheck
      # Marks a declared key the Hash doesn't have
      MISSING = Object.new.freeze
      private_constant :MISSING

      # @return [Class] the class a type folded into this check requires
      def self.shape = Hash

      # @param properties [Hash{String => #valid?}] checkers of the declared properties
      # @param required [Array<String>] required keys, all of them declared properties
      # @param sizes [Range] allowed number of properties
      # @param strict [Boolean] true when anything but a Hash fails (type: "object" folded in)
      def initialize(properties:, required:, sizes:, strict: false)
        @properties = properties
        @required_keys = required
        @keys = properties.keys.freeze
        @checks = properties.values.freeze
        @required = @keys.map { |key| required.include?(key) }.freeze
        @sizes = sizes
        @strict = strict
        freeze
      end

      # @return [ClosedObjectCheck] the same check, failing anything but a Hash
      def strict
        self.class.new(properties: @properties, required: @required_keys, sizes: @sizes, strict: true)
      end

      # @param data [Object] value to check; anything but a Hash passes unless strict
      # @return [Boolean] true when the Hash matches
      def valid?(data)
        return !@strict unless data.is_a?(Hash)

        found = 0
        index = 0
        while index < @keys.size
          value = data.fetch(@keys[index], MISSING)
          if MISSING.equal?(value)
            return reject(data) if @required[index]
          else
            return reject(data) unless @checks[index].valid?(value)

            found += 1
          end
          index += 1
        end
        (found == data.size && @sizes.cover?(found)) || reject(data)
      end

      private

      # json_schemer reads Symbol keys as Strings, so a false is certain only for a Hash with String keys; one with
      # Symbol keys is checked again with their Strings, and any other Hash throws {Root::DEFER}
      #
      # @param data [Hash] value being checked
      # @return [Boolean] false, or the answer for the Hash with String keys
      def reject(data)
        data.each_key do |key|
          next if key.is_a?(String)

          strings = StringKeys.call(data)
          throw Root::DEFER unless strings

          return valid?(strings)
        end
        false
      end
    end
  end
end
