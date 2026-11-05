# frozen_string_literal: true

module Versponse
  module Properties
    # An array of objects: inline (block of properties) or of another class (item:)
    #
    # @api private
    class Collection < Base
      include Container

      # @param item [Class, nil] class implementing the reference protocol
      # @param view [Symbol] view of item
      # @param options [Hash] see {Base#initialize}
      # @raise [Versponse::DefinitionError] when item does not implement the protocol
      def initialize(item: nil, view: :default, **options)
        super(**options)
        raise DefinitionError, "#{key}: item: must respond to to_ref and to_validation_schema" if item && !(item.respond_to?(:to_ref) && item.respond_to?(:to_validation_schema))

        @item = item
        @view = view.to_sym
      end

      # @param property [Versponse::Properties::Base] item property of an inline collection
      # @return [Versponse::Properties::Base] the property
      # @raise [Versponse::DefinitionError] for a collection with item:
      def add(property)
        raise DefinitionError, "#{key}: a collection with item: can not declare properties" if @item

        super
      end

      # @param context [Versponse::SchemaContext] schema generation context
      # @return [Hash] array schema
      def schema(context)
        items = @item ? References.schema(@item, view: @view, property: nil, context:) : inline_schema(context)
        nullable_type({"type" => "array", "items" => items}.merge(schema_options), context)
      end

      # @param version [String] requested version name
      # @return [Versponse::Steps::Nested, Versponse::Steps::Value] compiled step; items of non-Versponse classes pass through
      def step(version:)
        plan = if @item.nil?
          inline_plan(version)
        elsif References.versponse?(@item)
          LazyPlan.new(@item, version:, view: @view)
        end
        return value_step if plan.nil?

        Steps::Nested.new(key:, extractor:, condition:, plan:, collection: true)
      end
    end
  end
end
