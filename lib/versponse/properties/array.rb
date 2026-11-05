# frozen_string_literal: true

module Versponse
  module Properties
    # An array of scalar values
    #
    # @api private
    class Array < Base
      # @param type [Symbol, String] item type, one of {Field::TYPES}
      # @param item_schema_options [Hash] JSON Schema keywords of each item
      # @param options [Hash] see {Base#initialize}
      # @raise [Versponse::DefinitionError] for an unknown item type
      def initialize(type:, item_schema_options: {}, **options)
        super(**options)
        @item_type = type.to_s
        raise DefinitionError, "#{key}: type must be one of #{Field::TYPES.join(", ")}" unless Field::TYPES.include?(@item_type)

        @item_schema_options = Naming.camelize_keys(item_schema_options)
      end

      # @param context [Versponse::SchemaContext, nil] schema generation context
      # @return [Hash] JSON Schema of the array
      def schema(context)
        nullable_type({"type" => "array", "items" => {"type" => @item_type}.merge(@item_schema_options)}.merge(schema_options), context)
      end

      # @param version [String] unused by scalars
      # @return [Versponse::Steps::Value] compiled step; items are formatted by their format
      def step(version:)
        formatter = Versponse.configuration.formatters[@item_schema_options["format"]]
        return value_step unless formatter

        value_step(formatter: ->(items) { items.map { |item| item.nil? ? nil : formatter.call(item) } })
      end
    end
  end
end
