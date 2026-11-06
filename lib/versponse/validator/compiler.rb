# frozen_string_literal: true

module Versponse
  module Validator
    # Compiles a validation schema into a checker that responds to valid?(data)
    #
    # @api private
    class Compiler
      # Raised inside the compiler for a keyword or value it doesn't support
      Unsupported = Class.new(StandardError)

      # Keywords that don't affect validity
      ANNOTATIONS = %w[description title example examples default deprecated readOnly writeOnly $comment].freeze

      # Checker classes, each building itself from the keywords it owns
      CHECKS = [TypeCheck, ValueCheck, ObjectCheck, ArrayCheck, StringCheck, FormatCheck, NumberCheck, Combinator, Ref].freeze

      # Keywords naming a schema for "#Name" references, by JSON Schema version (see Configuration#anchor)
      ANCHORS = %w[$anchor $id id].freeze

      # Every keyword the compiler accepts
      KEYWORDS = (ANNOTATIONS + CHECKS.flat_map(&:keywords) + ANCHORS).freeze

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
        raise Unsupported, schema.inspect unless schema.is_a?(Hash) && (schema.keys - KEYWORDS).empty?

        name = anchor_name(schema)
        checker = All.for(CHECKS.filter_map { |check| check.build(schema, self) })
        @anchors[name] = checker if name
        checker
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
