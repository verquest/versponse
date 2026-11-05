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
      # @param expandable [Boolean] render items collapsed unless expanded (item: must be a Versponse class)
      # @param options [Hash] see {Base#initialize}
      # @raise [Versponse::DefinitionError] when item does not implement the protocol, or expandable: without a Versponse item:
      def initialize(item: nil, view: :default, expandable: false, **options)
        super(**options)
        raise DefinitionError, "#{key}: item: must respond to to_ref and to_validation_schema" if item && !(item.respond_to?(:to_ref) && item.respond_to?(:to_validation_schema))
        raise DefinitionError, "#{key}: expandable: needs item: with a Versponse class (mark an item one_of with expandable: instead)" if expandable && !References.versponse?(item)

        @item = item
        @view = view.to_sym
        @expandable = expandable
      end

      # @return [Boolean] true when items render collapsed unless expanded
      def expandable?
        @expandable
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

        Steps::Nested.new(key:, extractor:, condition:, plan:, collapsed_plan: items_collapsed_plan(version), collection: true)
      end

      # @param version [String] canonical version name
      # @param prefix [Array<String>] output keys leading here
      # @param stack [Array<Array(Class, Symbol)>] classes and views being walked
      # @return [Array<Array<String>>] expandable paths of the items
      def expandable_paths(version:, prefix:, stack:)
        return @items_one_of.expandable_paths(version:, prefix:, stack:) if @items_one_of
        return super unless @item

        path = prefix + [key]
        (expandable? ? [path] : []) + References.nested_paths(@item, view: @view, version:, prefix: path, stack:)
      end

      # @return [Boolean] true when the items (or the item one_of) are expandable
      def expandable_path?
        expandable? || (@items_one_of&.expandable? || false)
      end

      # @param version [String] canonical version name
      # @return [Array<Versponse::Properties::Base>] properties one segment below the items
      def path_children(version)
        return @items_one_of.path_children(version) if @items_one_of
        return super unless @item

        References.versponse?(@item) ? @item.resolve(version).properties_for(@view) : []
      end

      private

      def items_schema(context)
        return {"anyOf" => References.expandable_schemas(@item, view: @view, context:)} if expandable?
        return References.schema(@item, view: @view, property: nil, context:) if @item
        return @items_one_of.schema(context) if @items_one_of

        inline_schema(context)
      end

      def items_collapsed_plan(version)
        return References.collapsed_plan(@item, version) if expandable?

        @items_one_of.collapsed_dispatcher(version) if @items_one_of&.expandable?
      end

      def items_plan(version)
        return @items_one_of.dispatcher(version) if @items_one_of
        return inline_plan(version) if @item.nil?

        LazyPlan.new(@item, version:, view: @view) if References.versponse?(@item)
      end
    end
  end
end
