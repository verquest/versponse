# frozen_string_literal: true

module Versponse
  module Properties
    # An array of objects: inline (block of properties) or of another class (item:)
    #
    # @api private
    class Collection < Base
      # @return [Array<String>] keywords this property type writes itself
      def self.written_keywords = %w[items properties required].freeze

      # @return [Boolean] true: the subtree can render with its own context
      def self.context_option? = true

      include Container

      # @param item [Class, nil] class implementing the reference protocol
      # @param view [Symbol] view of item
      # @param expandable [Boolean] render items collapsed unless expanded (item: must be a Versponse class)
      # @param options [Hash] see {Base#initialize}
      # @raise [Versponse::DefinitionError] when item does not implement the protocol, expandable: without a Versponse item:,
      #   or context: with a non-Versponse item:
      def initialize(item: nil, view: :default, expandable: false, **options)
        super(**options)
        raise DefinitionError, "#{key}: item: must respond to to_ref and to_validation_schema" if item && !(item.respond_to?(:to_ref) && item.respond_to?(:to_validation_schema))
        raise DefinitionError, "#{key}: expandable: needs item: with a Versponse class (mark an item one_of with expandable: instead)" if expandable && !References.versponse?(item)

        @item = item
        @view = view.to_sym
        @expandable = expandable
        raise DefinitionError, "#{key}: context: needs a Versponse class to render with it" if context_override && @item && !References.versponse?(@item)
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
      # @param formatters [Hash{String => #call}] formatters by JSON Schema format, for the compiling class and version
      # @param policies [Versponse::ClassPolicies] class-level on_nil and on_error of the compiling class
      # @return [Versponse::Steps::Nested, Versponse::Steps::Value] compiled step; items of non-Versponse classes pass through
      def step(version:, formatters:, policies: ClassPolicies::NONE)
        plan = items_plan(version, formatters, policies)
        return value_step if plan.nil?

        collapse_if = (References.collapse_if(@item, version) if expandable?)
        Steps::Nested.new(key:, extractor:, condition:, plan:, collapsed_plan: items_collapsed_plan(version), collapse_if:, collection: true, context_override:)
      end

      # @param version [String] canonical version name
      # @param prefix [Array<String>] output keys leading here
      # @param stack [Array<Array(Class, Symbol)>] classes and views being walked
      # @return [Array<Array(Array<String>, Array<Class>)>] entries of the items
      def expandable_entries(version:, prefix:, stack:)
        return @items_one_of.expandable_entries(version:, prefix:, stack:) if @items_one_of
        return super unless @item

        path = prefix + [key]
        (expandable? ? [[path, [@item]]] : []) + References.nested_entries(@item, view: @view, version:, prefix: path, stack:)
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

        References.versponse?(@item) ? @item.versponse.resolve(version).properties_for(@view) : []
      end

      # @param version [String] canonical version name
      # @return [Array<String>] identifier keys of the item class, or the item one_of's collapsed keys
      def collapsed_path_keys(version)
        return @items_one_of.collapsed_path_keys(version) if @items_one_of

        expandable? ? @item.versponse.resolve(version).identifiers.keys : []
      end

      # @return [Array<Array(Class, Symbol, String)>] the item class, the item one_of's variants, or the inline children's targets
      def reference_targets
        return @items_one_of.reference_targets if @items_one_of
        return (References.versponse?(@item) ? [[@item, @view, key]] : []) if @item

        super
      end

      private

      def items_schema(context)
        return {"anyOf" => References.expandable_schemas(@item, view: @view, context:, key:)} if expandable?
        return References.schema(@item, view: @view, property: nil, context:, key:) if @item
        return @items_one_of.schema(context) if @items_one_of

        inline_schema(context)
      end

      def items_collapsed_plan(version)
        return References.collapsed_plan(@item, version) if expandable?

        @items_one_of.collapsed_dispatcher(version) if @items_one_of&.expandable?
      end

      def items_plan(version, formatters, policies)
        return @items_one_of.dispatcher(version) if @items_one_of
        return inline_plan(version, formatters, policies) if @item.nil?

        References.lazy_plan(@item, version:, view: @view, key:) if References.versponse?(@item)
      end
    end
  end
end
