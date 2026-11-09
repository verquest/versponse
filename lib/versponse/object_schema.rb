# frozen_string_literal: true

module Versponse
  # Builds an object schema from properties; every unconditional property is required (no required keyword when none is)
  #
  # @api private
  module ObjectSchema
    # @param properties [Array<Versponse::Properties::Base>] properties in output order
    # @param context [Versponse::SchemaContext] schema generation context
    # @param description [String, nil] schema description
    # @param schema_options [Hash] keywords merged last
    # @param additional_properties [Boolean] additionalProperties (config.default_additional_properties, false for collapsed shapes)
    # @return [Hash] object schema
    def self.build(properties, context, description: nil, schema_options: {}, additional_properties: Versponse.configuration.default_additional_properties)
      schema = {"type" => "object"}
      schema["description"] = description if description
      required = properties.reject(&:conditional?).map(&:key)
      # OpenAPI 3.0 and draft 4 need at least one item in required
      schema["required"] = required unless required.empty?
      schema["properties"] = properties.to_h { |property| [property.key, property.schema(context)] }
      schema["additionalProperties"] = additional_properties
      schema.merge(schema_options)
    end
  end
end
