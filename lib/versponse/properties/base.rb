# frozen_string_literal: true

module Versponse
  # Property types of the DSL
  module Properties
    # Shared behaviour of every property: output key, value source, condition and schema keywords
    #
    # @api private
    class Base
      # Schema allowing null next to a referenced schema
      NULL_SCHEMA = {"type" => "null"}.freeze

      # @return [Symbol] property name, used to read the value
      attr_reader :name
      # @return [String] key in the output and the schema
      attr_reader :key
      # @return [String, nil] source path given with map:
      attr_reader :map
      # @return [Proc, nil] value block called with (object, context)
      attr_reader :block
      # @return [Versponse::Condition, nil] if:/unless: condition
      attr_reader :condition
      # @return [Hash{String => Object}] camelized JSON Schema keywords
      attr_reader :schema_options

      # @param name [Symbol, String] property name and output key
      # @param block [Proc, nil] value block
      # @param options [Hash] map:, nullable:, if:, unless: and JSON Schema keywords in snake_case
      # @raise [Versponse::DefinitionError] when options conflict
      def initialize(name:, block: nil, **options)
        @name = name.to_sym
        @key = name.to_s.freeze
        @block = block
        @map = options.delete(:map)&.to_s
        @nullable = options.delete(:nullable) || false
        @condition = Condition.build(options.delete(:if), options.delete(:unless))
        check_options!(options)
        @schema_options = Naming.camelize_keys(options)
      end

      # @return [Boolean] true when the key is emitted only under a condition (so it is not required)
      def conditional?
        !condition.nil?
      end

      # @return [Boolean] true when null is allowed
      def nullable?
        @nullable
      end

      # Sets the value block declared with `source { |object, context| ... }` inside a container
      #
      # @param block [Proc] value block
      # @raise [Versponse::DefinitionError] when map: is also given or source is declared twice
      def source=(block)
        raise DefinitionError, "#{key}: use either source or map:, not both" if map
        raise DefinitionError, "#{key}: source is already declared" if @block

        @block = block
      end

      # A copy under another name, used by `reference property:`. A map: or block replaces the
      # source; without either the copy keeps its own source (its map:, block, or original name).
      #
      # @param name [Symbol, String] new name and output key
      # @param map [String, nil] replacement map:
      # @param block [Proc, nil] replacement value block
      # @param condition [Versponse::Condition, nil] condition of the copy (the original's is dropped)
      # @return [Versponse::Properties::Base] the copy
      def renamed(name:, map:, block:, condition:)
        dup.tap { |copy| copy.rename(name:, map:, block:, condition:) }
      end

      # @param context [Versponse::SchemaContext] schema generation context
      # @return [Hash] JSON Schema of the property
      def schema(context)
        raise NotImplementedError
      end

      # @param version [String] requested version name, used by nested classes
      # @return [#call] compiled plan step
      def step(version:)
        raise NotImplementedError
      end

      protected

      # @param name [Symbol, String] new name and output key
      # @param map [String, nil] replacement map:
      # @param block [Proc, nil] replacement value block
      # @param condition [Versponse::Condition, nil] condition of the copy
      # @return [void]
      def rename(name:, map:, block:, condition:)
        replace_source(map, block)
        @name = name.to_sym
        @key = name.to_s.freeze
        @condition = condition
      end

      private

      # A map: or block replaces the source; without either, keep the original name as the source
      def replace_source(map, block)
        if map || block
          @map = map
          @block = block
        elsif @map.nil? && @block.nil?
          @map = @key
        end
      end

      def check_options!(options)
        raise DefinitionError, "#{key}: required is computed automatically, use if: or unless: for optional keys" if options.key?(:required)
        raise DefinitionError, "#{key}: use either a block or map:, not both" if block && map
      end

      def extractor
        Extractors.for(name:, map:, block:)
      end

      def value_step(formatter: nil)
        Steps::Value.new(key:, extractor:, condition:, formatter:)
      end

      def nullable_type(schema, context = nil)
        return schema unless nullable?
        return schema.merge("nullable" => true) if nullable_keyword?(context)

        schema.merge("type" => [schema["type"], "null"])
      end

      # OpenAPI 3.0's `nullable` is not honoured next to allOf/enum/oneOf by validators,
      # so validation schemas always use the 3.1 forms
      def nullable_keyword?(context)
        Versponse.configuration.nullable_keyword? && !context&.validation?
      end

      def nullable_ref(schema, context)
        return schema unless nullable?
        return {"allOf" => [schema], "nullable" => true} if nullable_keyword?(context)

        {"anyOf" => [schema, NULL_SCHEMA]}
      end
    end
  end
end
