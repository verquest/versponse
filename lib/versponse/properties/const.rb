# frozen_string_literal: true

module Versponse
  module Properties
    # A constant value, always the same
    #
    # @api private
    class Const < Base
      # @param value [Object] constant value
      # @param options [Hash] see {Base#initialize}
      # @raise [Versponse::DefinitionError] with a block, map: or nullable:
      def initialize(value:, **options)
        super(**options)
        raise DefinitionError, "#{key}: const takes no block, map: or nullable:" if block || map || nullable?

        @constant = value.frozen? ? value : value.dup.freeze
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
      # @return [Versponse::Steps::Const] compiled step
      def step(version:)
        Steps::Const.new(key:, value: @constant, condition:)
      end
    end
  end
end
