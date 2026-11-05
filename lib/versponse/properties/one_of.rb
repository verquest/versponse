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

      # Sets the value block declared with `source { |object, context| ... }` inside one_of
      #
      # @param block [Proc] value block
      # @raise [Versponse::DefinitionError] when map: is also given or source is declared twice
      def source=(block)
        raise DefinitionError, "#{key}: use either source or map:, not both" if map
        raise DefinitionError, "#{key}: source is already declared" if @block

        @block = block
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
      # @return [Hash] oneOf schema; the discriminator is left out of validation schemas
      def schema(context)
        schemas = @variants.map { |variant| References.schema(variant.from, view: variant.view, property: nil, context:) }
        schema = {"oneOf" => schemas}
        if nullable? && nullable_keyword?(context)
          schema["nullable"] = true
        elsif nullable?
          schemas << NULL_SCHEMA
        end
        schema["discriminator"] = {"propertyName" => @discriminator} if @discriminator && !context.validation?
        schema.merge(schema_options)
      end

      # @param version [String] requested version name
      # @return [Versponse::Steps::OneOf] compiled step
      def step(version:)
        variants = @variants.map { |variant| [Array(variant.match).freeze, LazyPlan.new(variant.from, version:, view: variant.view)] }
        Steps::OneOf.new(key:, extractor:, condition:, variants: variants.freeze)
      end
    end
  end
end
