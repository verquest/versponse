# frozen_string_literal: true

module Versponse
  # Builds an object schema from properties; every unconditional property is required
  #
  # @api private
  module ObjectSchema
    # @param properties [Array<Versponse::Properties::Base>] properties in output order
    # @param context [Versponse::SchemaContext] schema generation context
    # @param description [String, nil] schema description
    # @param schema_options [Hash] keywords merged last
    # @return [Hash] object schema
    def self.build(properties, context, description: nil, schema_options: {})
      schema = {"type" => "object"}
      schema["description"] = description if description
      schema["required"] = properties.reject(&:conditional?).map(&:key)
      schema["properties"] = properties.to_h { |property| [property.key, property.schema(context)] }
      schema["additionalProperties"] = Versponse.configuration.default_additional_properties
      schema.merge(schema_options)
    end
  end
end
