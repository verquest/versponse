# frozen_string_literal: true

require "bigdecimal"

module Versponse
  module Validator
    # minimum, maximum, exclusiveMinimum, exclusiveMaximum and multipleOf, as json_schemer compares them
    #
    # @api private
    class NumberCheck
      # Keywords and the comparison data must pass against their value
      BOUNDS = {"minimum" => :>=, "maximum" => :<=, "exclusiveMinimum" => :>, "exclusiveMaximum" => :<}.freeze

      # @return [Array<String>] keywords this check owns
      def self.keywords = BOUNDS.keys + %w[multipleOf]

      # @param schema [Hash] schema
      # @param _compiler [Versponse::Validator::Compiler] unused
      # @return [NumberCheck, nil] the check, nil without number keywords
      def self.build(schema, _compiler)
        return unless keywords.any? { |keyword| schema.key?(keyword) }

        new(bounds(schema), schema["multipleOf"])
      end

      # A boolean exclusiveMinimum/exclusiveMaximum (draft 4, OpenAPI 3.0) makes minimum/maximum exclusive
      def self.bounds(schema)
        bounds = BOUNDS.filter_map { |keyword, operator| [operator, schema[keyword]] if schema[keyword].is_a?(Numeric) }
        bounds << [:>, schema["minimum"]] if schema["exclusiveMinimum"] == true && schema["minimum"].is_a?(Numeric)
        bounds << [:<, schema["maximum"]] if schema["exclusiveMaximum"] == true && schema["maximum"].is_a?(Numeric)
        bounds
      end
      private_class_method :bounds

      # @param bounds [Array<Array(Symbol, Numeric)>] comparisons data must pass
      # @param multiple_of [Numeric, nil] divisor, nil without multipleOf
      def initialize(bounds, multiple_of)
        @bounds = bounds.freeze
        @multiple_of = multiple_of
        freeze
      end

      # @param data [Object] value to check; anything but a Numeric passes
      # @return [Boolean] true when the number matches
      def valid?(data)
        return true unless data.is_a?(Numeric)

        @bounds.all? { |operator, value| data.public_send(operator, value) } && multiple?(data)
      end

      private

      def multiple?(data)
        @multiple_of.nil? || BigDecimal(data.to_s).modulo(@multiple_of).zero?
      end
    end
  end
end
