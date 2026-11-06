# frozen_string_literal: true

module Versponse
  module Properties
    # A polymorphic value whose variants are other response classes, picked with match: (===)
    #
    # @api private
    class OneOf < Base
      # @return [Array<String>] keywords this property type writes itself
      def self.written_keywords = %w[oneOf anyOf discriminator].freeze

      # One variant: response class, matcher and view
      Variant = Data.define(:from, :match, :view)

      # @param discriminator [String, Symbol, nil] OpenAPI discriminator property
      # @param expandable [Boolean] render variants collapsed unless expanded
      # @param options [Hash] see {Base#initialize}
      def initialize(discriminator: nil, expandable: false, **options)
        super(**options)
        @discriminator = discriminator&.to_s
        @expandable = expandable
        @variants = []
      end

      # @param _property [Versponse::Properties::Base] unused
      # @raise [Versponse::DefinitionError] always, variants are declared with reference
      def add(_property)
        raise DefinitionError, "#{key}: declare one_of variants with reference from:, match:"
      end

      # @param from [Class] Versponse response class
      # @param match [Class, Proc, Array<Class, Proc>] compared with === against the value
      # @param view [Symbol] view of from
      # @return [void]
      # @raise [Versponse::DefinitionError] without match: or with a non-Versponse class
      def add_variant(from:, match:, view: :default)
        raise DefinitionError, "#{key}: a one_of variant needs match:" if match.nil?
        raise DefinitionError, "#{key}: one_of variants must be Versponse response classes" unless References.versponse?(from)

        @variants << Variant.new(from:, match:, view: view.to_sym)
      end

      # @return [Boolean] true when at least one variant is declared
      def variants?
        !@variants.empty?
      end

      # @return [Boolean] true when variants render collapsed unless expanded
      def expandable?
        @expandable
      end

      # @param context [Versponse::SchemaContext] schema generation context
      # @return [Hash] oneOf schema (anyOf of full and collapsed forms when expandable); the discriminator,
      #   with a mapping built from each variant's const, is left out of validation schemas and of expandable
      #   one_of schemas (a collapsed payload carries the same value as the full form, so a mapping would
      #   send it to the full schema)
      #   A nullable one_of with a documented discriminator keeps null outside the discriminated oneOf, which
      #   would otherwise reject it.
      # @raise [Versponse::DefinitionError] when a variant lacks the discriminator const or two variants share a value
      def schema(context)
        schemas = @variants.flat_map { |variant| variant_schemas(variant, context) }
        keyword = expandable? ? "anyOf" : "oneOf"
        schema = if @discriminator && !expandable? && !context.validation?
          discriminator = {"propertyName" => @discriminator, "mapping" => discriminator_mapping(context.version)}
          nullable_ref({keyword => schemas, "discriminator" => discriminator}, context)
        else
          nullable_choice(keyword, schemas, context)
        end
        schema.merge(schema_options)
      end

      # @param version [String] canonical version name
      # @return [Versponse::VariantDispatcher] matching to the variants' full plans
      def dispatcher(version)
        variants = @variants.map { |variant| [Array(variant.match).freeze, References.lazy_plan(variant.from, version:, view: variant.view, key:)] }
        VariantDispatcher.new(variants, nullable: nullable?)
      end

      # @param version [String] canonical version name
      # @return [Versponse::VariantDispatcher] matching to the variants' collapsed plans (full plans when a variant's collapse_if is false)
      # @raise [Versponse::DefinitionError] when a variant class has no identifier
      def collapsed_dispatcher(version)
        variants = @variants.map { |variant| [Array(variant.match).freeze, collapsed_variant_plan(variant, version)] }
        VariantDispatcher.new(variants, nullable: nullable?)
      end

      # @param version [String] canonical version name
      # @param formatters [Hash{String => #call}] unused; variant classes compile with their own
      # @return [Versponse::Steps::OneOf] compiled step
      def step(version:, formatters:)
        collapsed_dispatcher = (collapsed_dispatcher(version) if expandable?)
        Steps::OneOf.new(key:, extractor:, condition:, dispatcher: dispatcher(version), collapsed_dispatcher:)
      end

      # @param version [String] canonical version name
      # @param prefix [Array<String>] output keys leading here
      # @param stack [Array<Array(Class, Symbol)>] classes and views being walked
      # @return [Array<Array<String>>] this path when expandable, plus every variant's paths
      def expandable_paths(version:, prefix:, stack:)
        path = prefix + [key]
        own = expandable? ? [path] : []
        own + @variants.flat_map { |variant| References.nested_paths(variant.from, view: variant.view, version:, prefix: path, stack:) }
      end

      # @return [Boolean] true when expandable
      def expandable_path?
        expandable?
      end

      # @param version [String] canonical version name
      # @return [Array<Versponse::Properties::Base>] properties of every variant's view
      def path_children(version)
        @variants.flat_map { |variant| variant.from.versponse.resolve(version).properties_for(variant.view) }
      end

      private

      def variant_schemas(variant, context)
        full = References.schema(variant.from, view: variant.view, property: nil, context:, key:)
        expandable? ? [full, collapsed_variant_schema(variant, context)] : [full]
      end

      def collapsed_variant_schema(variant, context)
        References.ensure_identifier!(variant.from, context.version)
        return References.schema(variant.from, view: :collapsed, property: nil, context:) unless @discriminator

        schema = variant.from.versponse.object_schema(version: context.version, view: :collapsed, context:)
        discriminator = {@discriminator => discriminator_property(variant, context.version).schema(context)}
        schema.merge("required" => [@discriminator, *schema["required"]], "properties" => discriminator.merge(schema["properties"]))
      end

      # Decides per value: an item one_of lets each item pick its own variant and shape
      def collapsed_variant_plan(variant, version)
        plan = References.collapsed_plan(variant.from, version)
        plan = DiscriminatedPlan.new(plan, key: @discriminator, value: discriminator_property(variant, version).value) if @discriminator
        collapse_if = References.collapse_if(variant.from, version)
        return plan unless collapse_if

        CollapseIfPlan.new(collapse_if, collapsed: plan, full: LazyPlan.new(variant.from, version:, view: variant.view))
      end

      def discriminator_mapping(version)
        @variants.each_with_object({}) do |variant, mapping|
          value = discriminator_property(variant, version).value.to_s
          raise DefinitionError, "#{key}: two variants share the discriminator value #{value.inspect}" if mapping.key?(value)

          mapping[value] = variant.from.to_ref(view: variant.view)
        end
      end

      def discriminator_property(variant, version)
        property = variant.from.versponse.resolve(version).properties_for(variant.view).find { |candidate| candidate.key == @discriminator }
        raise DefinitionError, "#{key}: #{variant.from.name} has no const #{@discriminator} for the discriminator" if property.nil?
        raise DefinitionError, "#{key}: #{variant.from.name}'s #{@discriminator} must be a const for the discriminator" unless property.is_a?(Const)

        property
      end
    end
  end
end
