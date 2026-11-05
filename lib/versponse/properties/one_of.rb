# frozen_string_literal: true

module Versponse
  module Properties
    # A polymorphic value whose variants are other response classes, picked with match: (===)
    #
    # @api private
    class OneOf < Base
      # One variant: response class, matcher and view
      Variant = Data.define(:from, :match, :view)

      # @param discriminator [String, Symbol, nil] OpenAPI discriminator property
      # @param options [Hash] see {Base#initialize}
      def initialize(discriminator: nil, **options)
        super(**options)
        @discriminator = discriminator&.to_s
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

      # @param context [Versponse::SchemaContext] schema generation context
      # @return [Hash] oneOf schema; the discriminator (with a mapping built from each variant's const)
      #   is left out of validation schemas
      # @raise [Versponse::DefinitionError] when a variant lacks the discriminator const or two variants share a value
      def schema(context)
        schemas = @variants.map { |variant| References.schema(variant.from, view: variant.view, property: nil, context:) }
        schema = {"oneOf" => schemas}
        if nullable? && nullable_keyword?(context)
          schema["nullable"] = true
        elsif nullable?
          schemas << NULL_SCHEMA
        end
        schema["discriminator"] = {"propertyName" => @discriminator, "mapping" => discriminator_mapping(context.version)} if @discriminator && !context.validation?
        schema.merge(schema_options)
      end

      # @param version [String] canonical version name
      # @return [Versponse::VariantDispatcher] matching for this one_of's variants
      def dispatcher(version)
        variants = @variants.map { |variant| [Array(variant.match).freeze, LazyPlan.new(variant.from, version:, view: variant.view)] }
        VariantDispatcher.new(variants, nullable: nullable?)
      end

      # @param version [String] canonical version name
      # @return [Versponse::Steps::OneOf] compiled step
      def step(version:)
        Steps::OneOf.new(key:, extractor:, condition:, dispatcher: dispatcher(version))
      end

      private

      def discriminator_mapping(version)
        @variants.each_with_object({}) do |variant, mapping|
          value = discriminator_value(variant, version)
          raise DefinitionError, "#{key}: two variants share the discriminator value #{value.inspect}" if mapping.key?(value)

          mapping[value] = variant.from.to_ref(view: variant.view)
        end
      end

      def discriminator_value(variant, version)
        property = variant.from.resolve(version).properties_for(variant.view).find { |candidate| candidate.key == @discriminator }
        raise DefinitionError, "#{key}: #{variant.from.name} has no const #{@discriminator} for the discriminator" if property.nil?
        raise DefinitionError, "#{key}: #{variant.from.name}'s #{@discriminator} must be a const for the discriminator" unless property.is_a?(Const)

        property.value.to_s
      end
    end
  end
end
