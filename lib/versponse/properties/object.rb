# frozen_string_literal: true

module Versponse
  module Properties
    # An inline object; its source is read by name or with map: ("." for the same object)
    #
    # @api private
    class Object < Base
      # @return [Array<String>] keywords this property type writes itself
      def self.written_keywords = %w[properties required].freeze

      # @return [Boolean] true: the subtree can render with its own context
      def self.context_option? = true

      include Container

      # @param context [Versponse::SchemaContext] schema generation context
      # @return [Hash] object schema
      def schema(context)
        nullable_type(inline_schema(context).merge(schema_options), context)
      end

      # @param version [String] requested version name
      # @param formatters [Hash{String => #call}] formatters by JSON Schema format, for the compiling class and version
      # @param policies [Versponse::ClassPolicies] class-level on_nil and on_error of the compiling class
      # @return [Versponse::Steps::Nested] compiled step with an inline child plan
      def step(version:, formatters:, policies: ClassPolicies::NONE)
        Steps::Nested.new(key:, extractor:, condition:, plan: inline_plan(version, formatters, policies), collection: false, context_override:)
      end
    end
  end
end
