# frozen_string_literal: true

module Versponse
  module Properties
    # An array of scalar values
    #
    # @api private
    class Array < Base
      # @return [Array<String>] keywords this property type writes itself
      def self.written_keywords = %w[items].freeze

      # @param type [Symbol, String, Array<Symbol, String>] item type: built-in ({FieldType::BUILT_IN}), custom, or a union of built-in types
      # @param item_schema_options [Hash] JSON Schema keywords of each item; they win over the custom type's
      # @param options [Hash] see {Base#initialize}
      # @raise [Versponse::DefinitionError] for an unknown item type or an invalid union
      def initialize(type:, item_schema_options: {}, **options)
        super(**options)
        check_keywords!(item_schema_options, label: "#{key} item_schema_options", written_keywords: [])
        @item_type, type_options = FieldType.resolve(type, key)
        @item_schema_options = type_options.merge(Naming.camelize_keys(item_schema_options))
      end

      # @param context [Versponse::SchemaContext, nil] schema generation context
      # @return [Hash] JSON Schema of the array; a union item type is an anyOf in OpenAPI 3.0 documents
      #   (an allOf with the items' own anyOf, when item_schema_options declare one)
      def schema(context)
        nullable_type({"type" => "array", "items" => items_schema(context)}.merge(schema_options), context)
      end

      # @param version [String] unused by scalars
      # @return [Versponse::Steps::Value] compiled step; items are formatted by their format
      def step(version:)
        formatter = Versponse.configuration.formatters[@item_schema_options["format"]]
        return value_step unless formatter

        value_step(formatter: ->(items) { items.map { |item| item.nil? ? nil : formatter.call(item) } })
      end

      private

      def items_schema(context)
        return FieldType.openapi30_union(@item_type, @item_schema_options) if openapi30_union?(@item_type, context)

        {"type" => @item_type}.merge(@item_schema_options)
      end
    end
  end
end
