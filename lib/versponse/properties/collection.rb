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
      # @raise [Versponse::DefinitionError] for a collection with item: or with an item one_of
      def add(property)
        raise DefinitionError, "#{key}: a collection with item: can not declare properties" if @item
        raise DefinitionError, "#{key}: one_of must be the only declaration in a collection block" if @items_one_of

        super
      end

      # @param one_of [Versponse::Properties::ItemOneOf] unnamed one_of typing every item
      # @return [Versponse::Properties::ItemOneOf] the one_of
      # @raise [Versponse::DefinitionError] when the collection has item:, properties or another one_of
      def items_one_of=(one_of)
        raise DefinitionError, "#{key}: a collection with item: can not declare one_of" if @item
        raise DefinitionError, "#{key}: one_of must be the only declaration in a collection block" if @items_one_of || !child_properties.empty?

        @items_one_of = one_of
      end

      # @param context [Versponse::SchemaContext] schema generation context
      # @return [Hash] array schema
      def schema(context)
        nullable_type({"type" => "array", "items" => items_schema(context)}.merge(schema_options), context)
      end

      # @param version [String] canonical version name
      # @return [Versponse::Steps::Nested, Versponse::Steps::Value] compiled step; items of non-Versponse classes pass through
      def step(version:)
        plan = items_plan(version)
        return value_step if plan.nil?

        Steps::Nested.new(key:, extractor:, condition:, plan:, collection: true)
      end

      private

      def items_schema(context)
        return References.schema(@item, view: @view, property: nil, context:) if @item
        return @items_one_of.schema(context) if @items_one_of

        inline_schema(context)
      end

      def items_plan(version)
        return @items_one_of.dispatcher(version) if @items_one_of
        return inline_plan(version) if @item.nil?

        LazyPlan.new(@item, version:, view: @view) if References.versponse?(@item)
      end
    end
  end
end
