# frozen_string_literal: true

module Versponse
  # Merges a property's schema keywords into the schema Versponse generated for it without losing the generated
  # combinators (a type union's anyOf, a nullable or wrapped $ref's anyOf/allOf), as verquest does: allOf lists
  # are joined, and an anyOf or oneOf on both sides go into allOf side by side.
  #
  # @api private
  module SchemaMerge
    # Combinators that can't be merged key by key
    EXCLUSIVE = %w[anyOf oneOf].freeze

    # @param schema [Hash] generated schema
    # @param options [Hash{String => Object}] the property's camelized schema keywords
    # @return [Hash] the merged schema
    def self.call(schema, options)
      clashes = EXCLUSIVE.select { |keyword| schema.key?(keyword) && options.key?(keyword) }
      return schema.merge(options) if clashes.empty? && !(schema.key?("allOf") && options.key?("allOf"))

      all_of = [*options["allOf"], *schema["allOf"]] + clashes.flat_map { |keyword| [{keyword => schema[keyword]}, {keyword => options[keyword]}] }
      schema.except(*clashes).merge(options.except(*clashes)).merge("allOf" => all_of)
    end
  end
end
