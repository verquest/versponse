# frozen_string_literal: true

module Versponse
  module OpenAPI
    # components.schemas of one build, remembering where each name came from
    #
    # @api private
    class ComponentSet
      # @return [ComponentSet] an empty set
      def initialize
        @schemas = {}
        @sources = {}
      end

      # @param name [String] component name
      # @param schema [Hash] component schema
      # @param source [String] where it came from, for the collision message
      # @return [void]
      # @raise [Versponse::DefinitionError] when the name is already taken
      def add(name, schema, source)
        raise DefinitionError, "Component #{name} from #{source} collides with #{@sources[name]}" if @schemas.key?(name)

        @schemas[name] = schema
        @sources[name] = source
      end

      # @return [Hash{String => Hash}] the schemas
      def to_h
        @schemas
      end
    end
  end
end
