# frozen_string_literal: true

module Versponse
  module Validator
    # items, minItems and maxItems
    #
    # @api private
    class ArrayCheck
      # @return [Array<String>] keywords this check owns
      def self.keywords = %w[items minItems maxItems]

      # @param schema [Hash] schema
      # @param compiler [Versponse::Validator::Compiler] compiles the items schema
      # @return [ArrayCheck, nil] the check, nil without array keywords
      def self.build(schema, compiler)
        return unless keywords.any? { |keyword| schema.key?(keyword) }

        new(compiler.compile(schema.fetch("items", true)), Range.new(schema["minItems"], schema["maxItems"]))
      end

      # @param items [#valid?] checker of every item
      # @param sizes [Range] allowed number of items
      def initialize(items, sizes)
        @items = items
        @sizes = sizes
        freeze
      end

      # @param data [Object] value to check; anything but an Array passes
      # @return [Boolean] true when the Array matches
      def valid?(data)
        return true unless data.is_a?(Array)

        @sizes.cover?(data.size) && data.all? { |item| @items.valid?(item) }
      end
    end
  end
end
