# frozen_string_literal: true

module Versponse
  # Orders properties as config.field_order says
  #
  # @api private
  module FieldOrder
    # Values accepted by config.field_order
    VALUES = %i[declaration alphabetical].freeze

    # :alphabetical matches blueprinter's sort_fields_by :name_asc: identifiers first, then by output key
    #
    # @param properties [Array<Versponse::Properties::Base>] properties in declaration order
    # @param identifiers [Array<String>] identifier keys, which go first when alphabetical
    # @return [Array<Versponse::Properties::Base>] the properties in the configured order
    def self.call(properties, identifiers: [])
      return properties if Versponse.configuration.field_order == :declaration

      first, rest = properties.partition { |property| identifiers.include?(property.key) }
      first + rest.sort_by(&:key)
    end
  end
end
