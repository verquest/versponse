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
      # @return [ObjectCheck, nil] the check, nil without object keywords
      def self.build(schema, compiler)
        return unless keywords.any? { |keyword| schema.key?(keyword) }

        new(
          properties: schema.fetch("properties", {}).transform_values { |property| compiler.compile(property) },
          required: schema.fetch("required", []),
          additional: compiler.compile(schema.fetch("additionalProperties", true)),
          sizes: Range.new(schema["minProperties"], schema["maxProperties"])
        )
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

      # A Hash with a non-String key is reported invalid, which hands it to json_schemer
      #
      # @param data [Object] value to check; anything but a Hash passes
      # @return [Boolean] true when the Hash matches
      def valid?(data)
        return true unless data.is_a?(Hash)

        @sizes.cover?(data.size) && @required.all? { |key| data.key?(key) } && data.all? { |key, value| member_valid?(key, value) }
      end

      private

      def member_valid?(key, value)
        key.is_a?(String) && @properties.fetch(key, @additional).valid?(value)
      end
    end
  end
end
