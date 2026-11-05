# frozen_string_literal: true

module Versponse
  module Properties
    # Another response class rendered in place, or a non-Versponse schema whose value passes through.
    # With property:, a Versponse class's property is reused as if it were declared here.
    #
    # @api private
    class Reference < Base
      # @param from [Class] class implementing the reference protocol
      # @param view [Symbol] view of from
      # @param property [Symbol, nil] reuse one property of from instead of the whole class
      # @param options [Hash] see {Base#initialize}
      # @raise [Versponse::DefinitionError] for an invalid from:, or nullable: with a versponse property:
      def initialize(from:, view: :default, property: nil, **options)
        super(**options)
        raise DefinitionError, "#{key}: from: must respond to to_ref and to_validation_schema" unless from.respond_to?(:to_ref) && from.respond_to?(:to_validation_schema)

        @from = from
        @view = view.to_sym
        @property = property&.to_s
        raise DefinitionError, "#{key}: nullable comes from the referenced property" if versponse_property? && nullable?
      end

      # @param context [Versponse::SchemaContext] schema generation context
      # @return [Hash] $ref or inlined schema; description and other keywords sit on the outer node
      # @raise [Versponse::PropertyNotFoundError] when a versponse property: does not exist
      def schema(context)
        return referenced_property_schema(context).merge(schema_options) if versponse_property?

        nullable_ref(References.schema(@from, view: @view, property: @property, context:), context).merge(schema_options)
      end

      # @param version [String] canonical version name
      # @return [Versponse::Steps::Nested, Versponse::Steps::Value, #call] compiled step
      # @raise [Versponse::PropertyNotFoundError] when a versponse property: does not exist
      def step(version:)
        return referenced_property(version).step(version:) if versponse_property?
        return value_step unless References.versponse?(@from)

        Steps::Nested.new(key:, extractor:, condition:, plan: LazyPlan.new(@from, version:, view: @view), collection: false)
      end

      private

      def versponse_property?
        !@property.nil? && References.versponse?(@from)
      end

      def referenced_property(version)
        original = @from.resolve(version).properties_for(@view).find { |property| property.key == @property } ||
          raise(PropertyNotFoundError, "#{key}: property #{@property} not found in #{@from.name} #{version}/#{@view}")
        original.renamed(name:, map:, block:, condition:)
      end

      def referenced_property_schema(context)
        copy = referenced_property(context.version)
        return {"$ref" => @from.to_ref(view: @view, property: @property)} unless context.validation?

        copy.schema(context)
      end
    end
  end
end
