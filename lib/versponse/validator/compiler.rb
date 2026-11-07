# frozen_string_literal: true

module Versponse
  module Validator
    # Compiles a validation schema into a checker that responds to valid?(data)
    #
    # @api private
    class Compiler
      # Raised inside the compiler for a keyword or value it doesn't support
      Unsupported = Class.new(StandardError)

      # Keywords that don't affect validity (x- extensions too). discriminator is not one: json_schemer uses it
      # to pick the oneOf variant it checks.
      ANNOTATIONS = %w[
        description title example examples default deprecated readOnly writeOnly $comment
        nullable xml externalDocs
      ].freeze

      # JSON Schema versions that ignore keywords next to $ref
      REF_ONLY = %i[draft4 draft6 draft7 openapi30].freeze

      # Checker classes, each building itself from the keywords it owns
      CHECKS = [TypeCheck, ValueCheck, ObjectCheck, ArrayCheck, StringCheck, FormatCheck, NumberCheck, Combinator, Ref].freeze

      # Keywords naming a schema for "#Name" references, by JSON Schema version (see Configuration#anchor)
      ANCHORS = %w[$anchor $id id].freeze

      # Keywords holding schemas that are only referenced (SelectionSchema keeps anchored originals there)
      DEFINITIONS = %w[$defs definitions].freeze

      # Every keyword the compiler accepts
      KEYWORDS = (ANNOTATIONS + CHECKS.flat_map(&:keywords) + ANCHORS + DEFINITIONS).freeze

      # @param schema [Hash] validation schema
      # @param schemer [JSONSchemer::Schema] json_schemer schema of the same Hash, used for patterns and formats
      # @return [#valid?, nil] the checker, or nil when the schema uses an unsupported keyword
      def self.call(schema, schemer)
        new(schemer).root(schema)
      rescue Unsupported
        nil
      end

      # @param schemer [JSONSchemer::Schema] json_schemer schema, used for patterns and formats
      def initialize(schemer)
        @schemer = schemer
        @anchors = {}
        @refs = []
        @compiled = {}.compare_by_identity
      end

      # @param schema [Hash] root validation schema
      # @return [#valid?] the checker
      # @raise [Unsupported] for an unsupported keyword or an unknown anchor
      def root(schema)
        checker = compile(schema)
        raise Unsupported, "unknown anchor" unless (@refs - @anchors.keys).empty?

        @anchors.freeze
        Root.new(checker)
      end

      # @param schema [Hash, Boolean] schema or subschema
      # @return [#valid?] the checker
      # @raise [Unsupported] for an unsupported keyword
      def compile(schema)
        return Constant.for(schema) if schema == true || schema == false
        raise Unsupported, schema.inspect unless schema.is_a?(Hash)

        @compiled[schema] = compile_hash(schema)
      end

      # @param schema [Hash, Boolean] a subschema of the root compiled with {#root}, the same object
      # @return [#valid?] its checker
      # @raise [Unsupported] for a Hash this compiler hasn't compiled
      def checker_for(schema)
        return Constant.for(schema) if schema == true || schema == false

        @compiled.fetch(schema) { raise Unsupported, "not compiled" }
      end

      # @param schema [Hash] schema or subschema
      # @return [#valid?] the checker
      def compile_hash(schema)
        schema = schema.slice("$ref", *ANCHORS) if schema.key?("$ref") && REF_ONLY.include?(Versponse.configuration.json_schema_version)
        DEFINITIONS.each { |keyword| schema[keyword].each_value { |definition| compile(definition) } if schema[keyword].is_a?(Hash) }
        raise Unsupported, schema.inspect unless schema.keys.all? { |key| KEYWORDS.include?(key) || key.start_with?("x-") }

        name = anchor_name(schema)
        checker = All.for(fold(CHECKS.filter_map { |check| check.build(schema, self) }))
        @anchors[name] = checker if name
        checker
      end

      # type: "object", "array" or "string" folds into the one check built for that shape, made strict, so a
      # value takes one check instead of two. With no such check (an unknown format builds none) or two (string
      # keywords and a format), the type check stays.
      #
      # @param checks [Array<#valid?>] checks built from one schema; TypeCheck comes first in CHECKS
      # @return [Array<#valid?>] the checks, with the type folded in when it can be
      def fold(checks)
        type = checks.first
        return checks unless type.is_a?(ClassCheck)

        owners = checks.select { |check| check.class.respond_to?(:shape) && check.class.shape == type.klass }
        return checks unless owners.one?

        checks.drop(1).map { |check| check.equal?(owners.first) ? check.strict : check }
      end

      # $id and id name an anchor only as a plain "#Name" fragment; other ids change the base URI
      #
      # @param schema [Hash] schema
      # @return [String, nil] the anchor name the schema declares
      # @raise [Unsupported] for an $id or id that isn't a plain-name fragment
      def anchor_name(schema)
        return schema["$anchor"] if schema.key?("$anchor")

        id = schema["$id"] || schema["id"]
        return if id.nil?
        raise Unsupported, "id #{id}" unless id.is_a?(String) && id.start_with?("#")

        id.delete_prefix("#")
      end

      # @param name [String] anchor name, without "#"
      # @return [Versponse::Validator::Ref] a reference resolved when validating
      def ref(name)
        @refs << name
        Ref.new(@anchors, name)
      end

      # @param pattern [String] pattern keyword
      # @return [Regexp] the Regexp json_schemer uses for it
      def regexp(pattern)
        @schemer.resolve_regexp(pattern)
      end

      # @param name [String] format keyword
      # @return [Proc, nil] json_schemer's format check, called with (data, name); nil for a format
      #   json_schemer doesn't know, which it treats as an annotation
      def format(name)
        @schemer.fetch_format(name, nil)
      end
    end
  end
end
