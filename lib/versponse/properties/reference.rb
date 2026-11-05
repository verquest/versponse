# frozen_string_literal: true

module Versponse
  module Properties
    # Another response class rendered in place, or a non-Versponse schema whose value passes through
    #
    # @api private
    class Reference < Base
      # @param from [Class] class implementing the reference protocol
      # @param view [Symbol] view of a Versponse class
      # @param property [Symbol, nil] one property of a non-Versponse class's schema
      # @param options [Hash] see {Base#initialize}
      # @raise [Versponse::DefinitionError] for an invalid from: or property:
      def initialize(from:, view: :default, property: nil, **options)
        super(**options)
        raise DefinitionError, "#{key}: from: must respond to to_ref and to_validation_schema" unless from.respond_to?(:to_ref) && from.respond_to?(:to_validation_schema)
        raise DefinitionError, "#{key}: property: only works with classes that are not Versponse responses" if property && References.versponse?(from)

        @from = from
        @view = view.to_sym
        @property = property
      end

      # @param context [Versponse::SchemaContext] schema generation context
      # @return [Hash] $ref or inlined schema, nullable when declared; description and other keywords sit on the outer node
      def schema(context)
        nullable_ref(References.schema(@from, view: @view, property: @property, context:), context).merge(schema_options)
      end

      # @param version [String] requested version name
      # @return [Versponse::Steps::Nested, Versponse::Steps::Value] compiled step
      def step(version:)
        return value_step unless References.versponse?(@from)

        Steps::Nested.new(key:, extractor:, condition:, plan: LazyPlan.new(@from, version:, view: @view), collection: false)
      end
    end
  end
end
