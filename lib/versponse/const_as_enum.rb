# frozen_string_literal: true

module Versponse
  # Draft 4 and OpenAPI 3.0 have no const keyword, so every generated const (property options and nested
  # schemas included) becomes a one-value enum. Data keywords keep their values, and name maps keep their names.
  #
  # @api private
  module ConstAsEnum
    # Keywords whose values are data, not schemas
    DATA_KEYWORDS = %w[example examples default enum const].freeze

    # Keywords whose keys are names, with a schema for each
    NAME_MAPS = %w[properties patternProperties $defs definitions dependentSchemas].freeze

    # @param schema [Object] generated schema
    # @return [Object] a copy with every const as a one-value enum (an existing enum keeps only that value)
    def self.call(schema)
      case schema
      when Hash then convert(schema)
      when Array then schema.map { |item| call(item) }
      else schema
      end
    end

    def self.convert(schema)
      converted = schema.to_h do |key, item|
        next [key, item] if DATA_KEYWORDS.include?(key)
        next [key, item.transform_values { |child| call(child) }] if NAME_MAPS.include?(key) && item.is_a?(Hash)

        [key, call(item)]
      end
      return converted unless converted.key?("const")

      value = converted.delete("const")
      converted.merge("enum" => converted.key?("enum") ? converted["enum"].select { |allowed| allowed == value } : [value])
    end
    private_class_method :convert
  end
end
