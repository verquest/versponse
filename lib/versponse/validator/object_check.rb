# frozen_string_literal: true

module Versponse
  module Validator
    # properties, required, additionalProperties, minProperties and maxProperties
    #
    # @api private
    class ObjectCheck
      # @return [Array<String>] keywords this check owns
      def self.keywords = %w[properties required additionalProperties minProperties maxProperties]

      # @return [Class] the class a type folded into this check requires
      def self.shape = Hash

      # @param schema [Hash] schema
      # @param compiler [Versponse::Validator::Compiler] compiles subschemas
      # @return [ObjectCheck, ClosedObjectCheck, nil] the check, nil without object keywords
      def self.build(schema, compiler)
        return unless keywords.any? { |keyword| schema.key?(keyword) }

        properties = schema.fetch("properties", {}).transform_values { |property| compiler.compile(property) }
        required = schema.fetch("required", [])
        sizes = Range.new(schema["minProperties"], schema["maxProperties"])
        if schema["additionalProperties"] == false && required.all? { |key| properties.key?(key) }
          return ClosedObjectCheck.new(properties:, required:, sizes:)
        end

        new(properties:, required:, additional: compiler.compile(schema.fetch("additionalProperties", true)), sizes:)
      end

      # @param properties [Hash{String => #valid?}] checkers of named properties
      # @param required [Array<String>] required keys
      # @param additional [#valid?] checker of other properties
      # @param sizes [Range] allowed number of properties
      # @param strict [Boolean] true when anything but a Hash fails (type: "object" folded in)
      def initialize(properties:, required:, additional:, sizes:, strict: false)
        @properties = properties.freeze
        @required = required.freeze
        @additional = additional
        @sizes = sizes
        @strict = strict
        freeze
      end

      # @return [ObjectCheck] the same check, failing anything but a Hash
      def strict
        self.class.new(properties: @properties, required: @required, additional: @additional, sizes: @sizes, strict: true)
      end

      # A Hash with Symbol keys is checked with their Strings; any other non-String key throws {Root::DEFER}, which
      # hands it to json_schemer
      #
      # @param data [Object] value to check; anything but a Hash passes unless strict
      # @return [Boolean] true when the Hash matches
      def valid?(data)
        return !@strict unless data.is_a?(Hash)
        return reject(data) unless @sizes.cover?(data.size)

        @required.each { |key| return reject(data) unless data.key?(key) }
        data.each do |key, value|
          return with_string_keys(data) unless key.is_a?(String)
          return false unless (@properties[key] || @additional).valid?(value)
        end
        true
      end

      private

      # json_schemer reads Symbol keys as Strings, so a false is certain only for a Hash with String keys; one with
      # Symbol keys is checked again with their Strings
      #
      # @param data [Hash] value being checked
      # @return [Boolean] false, or the answer for the Hash with String keys
      def reject(data)
        data.each_key { |key| return with_string_keys(data) unless key.is_a?(String) }
        false
      end

      # @param data [Hash] value with a non-String key
      # @return [Boolean] the answer for the Hash with String keys; throws {Root::DEFER} when the keys can't all be
      #   read as Strings (inside oneOf or not, a false would be read as a real answer)
      def with_string_keys(data)
        strings = StringKeys.call(data)
        throw Root::DEFER unless strings

        valid?(strings)
      end
    end
  end
end
