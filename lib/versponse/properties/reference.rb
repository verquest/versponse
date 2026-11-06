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
      # @param expandable [Boolean] render collapsed unless expanded
      # @param options [Hash] see {Base#initialize}
      # @raise [Versponse::DefinitionError] for an invalid from:, nullable: with a versponse property:,
      #   or expandable: on a foreign class or with property:
      def initialize(from:, view: :default, property: nil, expandable: false, **options)
        super(**options)
        raise DefinitionError, "#{key}: from: must respond to to_ref and to_validation_schema" unless from.respond_to?(:to_ref) && from.respond_to?(:to_validation_schema)

        @from = from
        @view = view.to_sym
        @property = property&.to_s
        @expandable = expandable
        raise DefinitionError, "#{key}: nullable comes from the referenced property" if versponse_property? && nullable?
        raise DefinitionError, "#{key}: expandable: needs a Versponse class without property:" if expandable && (!References.versponse?(from) || @property)
      end

      # @return [Boolean] true when the reference renders collapsed unless expanded
      def expandable?
        @expandable
      end

      # @param context [Versponse::SchemaContext] schema generation context
      # @return [Hash] $ref or inlined schema (anyOf full/collapsed when expandable); keywords sit on the outer node,
      #   beside an allOf around a bare $ref in OpenAPI 3.0 documents, which ignore $ref siblings
      # @raise [Versponse::DefinitionError] when a property: does not exist
      def schema(context)
        return referenced_property_schema(context).merge(schema_options) if versponse_property?

        check_foreign_property!(context.version) if @property
        return nullable_choice("anyOf", References.expandable_schemas(@from, view: @view, context:), context).merge(schema_options) if expandable?

        schema = nullable_ref(References.schema(@from, view: @view, property: @property, context:), context)
        schema = {"allOf" => [schema]} if schema.key?("$ref") && schema_options.any? && nullable_keyword?(context)
        schema.merge(schema_options)
      end

      # @param version [String] canonical version name
      # @return [Versponse::Steps::Nested, Versponse::Steps::Value, #call] compiled step
      # @raise [Versponse::DefinitionError] when a versponse property: does not exist
      def step(version:)
        return referenced_property(version).step(version:) if versponse_property?
        return value_step unless References.versponse?(@from)

        collapsed_plan = (References.collapsed_plan(@from, version) if expandable?)
        collapse_if = (References.collapse_if(@from, version) if expandable?)
        Steps::Nested.new(key:, extractor:, condition:, plan: LazyPlan.new(@from, version:, view: @view), collapsed_plan:, collapse_if:, collection: false)
      end

      # @param version [String] canonical version name
      # @param prefix [Array<String>] output keys leading here
      # @param stack [Array<Array(Class, Symbol)>] classes and views being walked
      # @return [Array<Array<String>>] this path when expandable, plus the referenced class's paths
      def expandable_paths(version:, prefix:, stack:)
        return referenced_property(version).expandable_paths(version:, prefix:, stack:) if versponse_property?

        path = prefix + [key]
        (expandable? ? [path] : []) + References.nested_paths(@from, view: @view, version:, prefix: path, stack:)
      end

      # @return [Boolean] true when expandable
      def expandable_path?
        expandable?
      end

      # @param version [String] canonical version name
      # @return [Array<Versponse::Properties::Base>] properties of the referenced class's view
      def path_children(version)
        References.versponse?(@from) ? @from.versponse.resolve(version).properties_for(@view) : []
      end

      # @param version [String] canonical version name
      # @return [Versponse::Properties::Base] the reused copy for a versponse property:, otherwise self
      def path_target(version)
        versponse_property? ? referenced_property(version) : self
      end

      private

      def versponse_property?
        !@property.nil? && References.versponse?(@from)
      end

      def referenced_property(version)
        original = @from.versponse.resolve(version).properties_for(@view).find { |property| property.key == @property } ||
          raise(DefinitionError, "#{key}: property #{@property} not found in #{@from.name} #{version}/#{@view}")
        original.renamed(name:, map:, block:, condition:)
      end

      # A foreign class (a verquest request) answers nil for a property it doesn't have
      def check_foreign_property!(version)
        return unless @from.to_validation_schema(version:, property: @property).nil?

        raise DefinitionError, "#{key}: property #{@property} not found in #{@from.name} #{version}"
      end

      def referenced_property_schema(context)
        copy = referenced_property(context.version)
        return {"$ref" => @from.to_ref(view: @view, property: @property)} unless context.validation?

        copy.schema(context)
      end
    end
  end
end
