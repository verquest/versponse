# frozen_string_literal: true

module Versponse
  module OpenAPI
    # rswag's config.openapi_specs: maps "name/version.json" keys to lazily built, memoized,
    # symbol-keyed documents (rswag merges paths with symbol keys). Security scheme "type" and "in"
    # values are symbols too: rswag compares them with :apiKey and :header to send API key headers.
    class RswagSpecs
      include Enumerable

      # @param documents [Array<Class>] Versponse::OpenAPI::Document subclasses with document_name and versions
      # @raise [Versponse::DefinitionError] when a document has no document_name
      def initialize(documents)
        @entries = documents.each_with_object({}) do |document, entries|
          raise DefinitionError, "#{document.name} needs document_name for rswag" unless document.document_name

          document.document_versions.each { |version| entries["#{document.document_name}/#{version}.json"] = [document, version] }
        end
        @built = {}
      end

      # @param key [String] e.g. "public_api/2025-09.json" (.yaml and .yml are accepted too)
      # @return [Hash, nil] the symbol-keyed document, nil for an unknown key (rswag checks for nil); built on
      #   first access and kept, because rswag merges its paths into it (so load response classes first)
      def [](key)
        key = normalize(key)
        return unless @entries.key?(key)

        @built[key] ||= symbolize_security_schemes(symbolize(build(key)))
      end

      # @param key [String] document key
      # @return [Hash] the symbol-keyed document
      # @raise [KeyError] for an unknown key
      def fetch(key)
        self[key] || raise(KeyError, "Unknown OpenAPI document #{key}")
      end

      # @yieldparam key [String] document key
      # @yieldparam document [Hash] symbol-keyed document
      # @return [Enumerator, void] an enumerator without a block
      def each
        return enum_for(:each) unless block_given?

        keys.each { |key| yield key, self[key] }
      end

      # @return [Array<String>] every document key
      def keys
        @entries.keys
      end

      # @return [Array<Hash>] every document
      def values
        keys.map { |key| self[key] }
      end

      # @param key [String] document key
      # @return [Boolean] whether the key is known
      def key?(key)
        @entries.key?(normalize(key))
      end

      # @return [Boolean] true when no document is declared
      def empty?
        @entries.empty?
      end

      private

      def normalize(key)
        key.to_s.sub(/\.ya?ml\z/, ".json")
      end

      def build(key)
        document, version = @entries.fetch(key)
        document.build(version:)
      end

      def symbolize_security_schemes(document)
        document.dig(:components, :securitySchemes)&.each_value do |scheme|
          scheme.slice(:type, :in).each { |name, value| scheme[name] = value.to_sym }
        end
        document
      end

      def symbolize(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_sym, symbolize(item)] }
        when Array then value.map { |item| symbolize(item) }
        else value
        end
      end
    end
  end
end
