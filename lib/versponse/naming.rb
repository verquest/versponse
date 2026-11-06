# frozen_string_literal: true

module Versponse
  # Converts snake_case names to the camelCase and PascalCase used in schemas
  #
  # @api private
  module Naming
    # @param name [String, Symbol] snake_case name
    # @return [String] camelCase name
    def self.camelize(name)
      first, *rest = name.to_s.split("_")
      first + rest.map(&:capitalize).join
    end

    # Keywords whose values are data, not schema, so their nested keys are kept as given
    VALUE_KEYWORDS = %w[example examples default const enum].freeze

    # Keywords whose keys are user-chosen names, kept as given; only their Hash values are schemas
    NAME_MAPS = %w[properties patternProperties $defs dependentRequired dependentSchemas].freeze

    # @param hash [Hash] snake_case keys, nested schema Hashes and Arrays of them included
    # @return [Hash{String => Object}] camelCase String keys at every schema level; keys of
    #   name maps (properties, patternProperties, $defs, dependentRequired, dependentSchemas) are only stringified,
    #   and a Regexp pattern becomes its source
    def self.camelize_keys(hash)
      hash.to_h do |key, value|
        key = camelize(key)
        [key, camelize_value(key, value)]
      end
    end

    def self.camelize_value(key, value)
      return value if VALUE_KEYWORDS.include?(key)
      return value.source if key == "pattern" && value.is_a?(Regexp)
      return camelize_name_map(value) if NAME_MAPS.include?(key) && value.is_a?(Hash)

      camelize_nested(value)
    end

    def self.camelize_nested(value)
      case value
      when Hash then camelize_keys(value)
      when Array then value.map { |element| camelize_nested(element) }
      else value
      end
    end

    def self.camelize_name_map(map)
      map.to_h { |name, value| [name.to_s, value.is_a?(Hash) ? camelize_keys(value) : value] }
    end

    private_class_method :camelize_value, :camelize_nested, :camelize_name_map

    # Capitals inside a part are kept, so :fullDetails and :full_details both give "FullDetails"
    #
    # @param name [String, Symbol] snake_case or camelCase name
    # @return [String] PascalCase name
    def self.pascalize(name)
      name.to_s.split("_").map { |part| part.sub(/\A[a-z]/, &:upcase) }.join
    end
  end
end
