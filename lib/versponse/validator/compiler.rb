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

      # Every keyword the compiler accepts
      KEYWORDS = (ANNOTATIONS + CHECKS.flat_map(&:keywords) + ["$anchor"]).freeze

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
        checker
      end

      # @param schema [Hash, Boolean] schema or subschema
      # @return [#valid?] the checker
      # @raise [Unsupported] for an unsupported keyword
      def compile(schema)
        return Constant.for(schema) if schema == true || schema == false
        raise Unsupported, schema.inspect unless schema.is_a?(Hash) && (schema.keys - KEYWORDS).empty?

        checker = All.for(CHECKS.filter_map { |check| check.build(schema, self) })
        @anchors[schema["$anchor"]] = checker if schema.key?("$anchor")
        checker
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
      # @return [Proc] json_schemer's format check, called with (data, name)
      # @raise [Unsupported] for a format json_schemer doesn't know
      def format(name)
        @schemer.fetch_format(name) { raise Unsupported, "format #{name}" }
      end
    end
  end
end
