# frozen_string_literal: true

module Versponse
  module Properties
    # A scalar value
    #
    # @api private
    class Field < Base
      # Allowed field types; "object" is a free-form map whose value passes through (describe it with additional_properties:)
      TYPES = %w[string number integer boolean object].freeze

      # @param type [Symbol, String] one of {TYPES}
      # @param options [Hash] see {Base#initialize}
      # @raise [Versponse::DefinitionError] for an unknown type
      def initialize(type:, **options)
        super(**options)
        @type = type.to_s
        raise DefinitionError, "#{key}: type must be one of #{TYPES.join(", ")}" unless TYPES.include?(@type)
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
