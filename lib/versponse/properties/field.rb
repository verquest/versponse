# frozen_string_literal: true

module Versponse
  module Properties
    # A scalar value
    #
    # @api private
    class Field < Base
      # @return [Boolean] true: nil values can be replaced
      def self.default_option? = true

      # @param type [Symbol, String, Array<Symbol, String>] a built-in type ({FieldType::BUILT_IN}; "object" is a free-form map whose
      #   value passes through), a custom one from config.custom_field_types, or a union of two or more built-in types
      # @param options [Hash] see {Base#initialize}; they win over the custom type's schema options
      # @raise [Versponse::DefinitionError] for an unknown type or an invalid union
      def initialize(type:, **options)
        super(**options)
        @type, type_options = FieldType.resolve(type, key)
        @schema_options = type_options.merge(schema_options)
        check_default!
      end

      # @param context [Versponse::SchemaContext, nil] schema generation context
      # @return [Hash] JSON Schema of the field; a type union is a type array, or an anyOf of single types in
      #   OpenAPI 3.0 documents, with keywords on the outer node and nullable on each branch. nullable: never
      #   changes a declared any_of, so a nullable field's any_of must list {"type" => "null"} itself.
      def schema(context)
        options = (nullable? && schema_options["enum"]) ? schema_options.merge("enum" => schema_options["enum"] | [nil]) : schema_options
        return nullable_type({"type" => @type}.merge(options), context) unless openapi30_union?(@type, context)

        FieldType.openapi30_union(@type, options, nullable: nullable?)
      end

      # @param version [String] unused by scalars
      # @param formatters [Hash{String => #call}] formatters by JSON Schema format, for the compiling class and version
      # @param policies [Versponse::ClassPolicies] class-level on_nil and on_error of the compiling class
      # @return [Versponse::Steps::Value] compiled step with the formatter of its format
      def step(version:, formatters:, policies: ClassPolicies::NONE)
        value_step(formatter: formatters[schema_options["format"]], policies:)
      end
    end
  end
end
