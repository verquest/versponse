# frozen_string_literal: true

module Versponse
  module Properties
    # An inline object; its source is read by name or with map: ("." for the same object)
    #
    # @api private
    class Object < Base
      # @return [Array<String>] keywords this property type writes itself
      def self.written_keywords = %w[properties required].freeze

      include Container

      # @param context [Versponse::SchemaContext] schema generation context
      # @return [Hash] object schema
      def schema(context)
        nullable_type(inline_schema(context).merge(schema_options), context)
      end

      # @param version [String] requested version name
      # @return [Versponse::Steps::Nested] compiled step with an inline child plan
      def step(version:)
        Steps::Nested.new(key:, extractor:, condition:, plan: inline_plan(version), collection: false)
      end
    end
  end
end
