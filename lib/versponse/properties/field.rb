# frozen_string_literal: true

module Versponse
  module Properties
    # A scalar value
    #
    # @api private
    class Field < Base
      # @param type [Symbol, String] a built-in type ({FieldType::BUILT_IN}; "object" is a free-form map whose
      #   value passes through) or a custom one from config.custom_field_types
      # @param options [Hash] see {Base#initialize}; they win over the custom type's schema options
      # @raise [Versponse::DefinitionError] for an unknown type
      def initialize(type:, **options)
        super(**options)
        @type, type_options = FieldType.resolve(type, key)
        @schema_options = type_options.merge(schema_options)
      end

      # @param context [Versponse::SchemaContext, nil] schema generation context
      # @return [Hash] JSON Schema of the field
      def schema(context)
        nullable_type({"type" => @type}.merge(schema_options), context)
      end

      # @param version [String] unused by scalars
      # @return [Versponse::Steps::Value] compiled step with the formatter of its format
      def step(version:)
        value_step(formatter: Versponse.configuration.formatters[schema_options["format"]])
      end
    end
  end
end
