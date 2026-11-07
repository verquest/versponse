# frozen_string_literal: true

module Versponse
  module Validator
    # properties, required, additionalProperties, minProperties and maxProperties
    #
    # @api private
    class ObjectCheck
      # @return [Array<String>] keywords this check owns
      def self.keywords = %w[properties required additionalProperties minProperties maxProperties]

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
      def initialize(properties:, required:, additional:, sizes:)
        @properties = properties.freeze
        @required = required.freeze
        @additional = additional
        @sizes = sizes
        freeze
      end

      # A Hash with a non-String key throws {Root::DEFER}, which hands it to json_schemer
      #
      # @param data [Object] value to check; anything but a Hash passes
      # @return [Boolean] true when the Hash matches
      def valid?(data)
        return true unless data.is_a?(Hash)
        return reject(data) unless @sizes.cover?(data.size)

        @required.each { |key| return reject(data) unless data.key?(key) }
        data.each do |key, value|
          throw Root::DEFER unless key.is_a?(String)
          return false unless (@properties[key] || @additional).valid?(value)
        end
        true
      end

      private

      # json_schemer reads Symbol keys as Strings, so a false is certain only for a Hash with String keys;
      # any other Hash throws {Root::DEFER} (inside oneOf or not, a false would be read as a real answer)
      #
      # @param data [Hash] value being checked
      # @return [false]
      def reject(data)
        data.each_key { |key| throw Root::DEFER unless key.is_a?(String) }
        false
      end
    end
  end
end
