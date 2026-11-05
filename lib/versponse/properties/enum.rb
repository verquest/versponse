# frozen_string_literal: true

module Versponse
  module Properties
    # A value from a fixed list
    #
    # @api private
    class Enum < Base
      # @param values [Array] allowed values
      # @param options [Hash] see {Base#initialize}
      # @raise [Versponse::DefinitionError] when values is empty
      def initialize(values:, **options)
        super(**options)
        raise DefinitionError, "#{key}: values must be a non-empty Array" unless values.is_a?(::Array) && !values.empty?

        @values = values.dup.freeze
      end

      # @param context [Versponse::SchemaContext, nil] schema generation context
      # @return [Hash] JSON Schema of the enum
      def schema(context)
        schema = {"enum" => @values}.merge(schema_options)
        return schema unless nullable?
        return schema.merge("nullable" => true) if nullable_keyword?(context)

        schema.merge("enum" => @values | [nil])
      end

      # @param version [String] unused by scalars
      # @return [Versponse::Steps::Value] compiled step
      def step(version:)
        value_step
      end
    end
  end
end
