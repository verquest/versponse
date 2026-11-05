# frozen_string_literal: true

module Versponse
  module Validator
    # const and enum, compared with == as json_schemer does
    #
    # @api private
    class ValueCheck
      # @return [Array<String>] keywords this check owns
      def self.keywords = %w[const enum]

      # @param schema [Hash] schema
      # @param _compiler [Versponse::Validator::Compiler] unused
      # @return [ValueCheck, nil] the check, nil without const and enum
      def self.build(schema, _compiler)
        return unless schema.key?("const") || schema.key?("enum")

        new(schema.key?("const") ? [schema["const"]] : nil, schema["enum"])
      end

      # @param const [Array, nil] the const wrapped in an Array, nil without const
      # @param enum [Array, nil] allowed values, nil without enum
      def initialize(const, enum)
        @const = const
        @enum = enum
        freeze
      end

      # @param data [Object] value to check
      # @return [Boolean] true when data equals the const and is in the enum
      def valid?(data)
        (@const.nil? || @const.first == data) && (@enum.nil? || @enum.include?(data))
      end
    end
  end
end
