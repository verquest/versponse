# frozen_string_literal: true

module Versponse
  module Properties
    # A constant value, always the same
    #
    # @api private
    class Const < Base
      # @return [Array<String>] keywords this property type writes itself
      def self.written_keywords = %w[const enum].freeze

      # @param value [Object] constant value
      # @param options [Hash] see {Base#initialize}
      # @raise [Versponse::DefinitionError] with a block, map: or nullable: (a response constant never reads the object)
      def initialize(value:, **options)
        super(**options)
        raise DefinitionError, "#{key}: const never reads the object, so it takes no map: or block (use enum or field for computed values)" if block || map
        raise DefinitionError, "#{key}: const always renders its value, so it can't be nullable (use enum with nil)" if nullable?

        @constant = DeepFreeze.call(value)
      end

      # @return [Object] the frozen constant value
      def value
        @constant
      end

      # @param _context [Versponse::SchemaContext] unused
      # @return [Hash] const schema, or a one-value enum for OpenAPI 3.0
      def schema(_context)
        keyword = Versponse.configuration.const_keyword? ? {"const" => @constant} : {"enum" => [@constant]}
        keyword.merge(schema_options)
      end

      # @param version [String] unused by constants
      # @param formatters [Hash{String => #call}] unused by constants
      # @param policies [Versponse::ClassPolicies] class-level on_nil and on_error of the compiling class
      # @return [Versponse::Steps::Const] compiled step
      def step(version:, formatters:, policies: ClassPolicies::NONE)
        Steps::Const.new(key:, value: @constant, condition:)
      end
    end
  end
end
