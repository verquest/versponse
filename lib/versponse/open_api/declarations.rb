# frozen_string_literal: true

module Versponse
  module OpenAPI
    # Everything a document class declares. Subclasses get a copy, so they inherit and extend it.
    #
    # @api private
    class Declarations
      # One response or request source: an explicit list, or a namespace (Module or String) resolved at build
      Source = Data.define(:classes, :namespace)
      # One named wrapper component
      Wrapper = Data.define(:name, :klass, :root, :collection, :meta, :view)

      # @return [String, nil] rswag key prefix
      attr_accessor :document_name
      # @return [String, nil] openapi field, nil for the version config.json_schema_version writes
      attr_accessor :openapi
      # @return [Hash, Proc, nil] externalDocs
      attr_accessor :external_docs
      # @return [Array, Proc, nil] top-level security
      attr_accessor :security
      # @return [Hash, Proc, nil] top-level webhooks
      attr_accessor :webhooks
      # @return [Array<String>] versions exposed to rswag (empty = any version)
      attr_accessor :versions
      # @return [Array<Hash, Proc>] info layers, a subclass's after its parent's, merged in order at build
      attr_reader :info
      # @return [Array<Hash>] servers
      attr_reader :servers
      # @return [Array<Hash>] tags
      attr_reader :tags
      # @return [Hash{String => Hash, Proc}] securitySchemes by name
      attr_reader :security_schemes
      # @return [Array<Source>] response sources
      attr_reader :response_sources
      # @return [Array<Source>] request sources
      attr_reader :request_sources
      # @return [Hash{String => Wrapper}] wrapper components by name
      attr_reader :wrappers
      # @return [Hash{String => Hash, Proc}] hand-written components by name
      attr_reader :schemas
      # @return [Array<Proc>] finalize hooks
      attr_reader :finalizers

      # @return [Declarations] empty declarations
      def initialize
        @openapi = nil
        @versions = []
        @info = []
        @servers = []
        @tags = []
        @security_schemes = {}
        @response_sources = []
        @request_sources = []
        @wrappers = {}
        @schemas = {}
        @finalizers = []
        @claimed = Set.new
      end

      # @param other [Declarations] declarations being copied
      # @return [void]
      def initialize_copy(other)
        super
        @versions = other.versions.dup
        @info = other.info.dup
        @servers = other.servers.dup
        @tags = other.tags.dup
        @security_schemes = other.security_schemes.dup
        @response_sources = other.response_sources.dup
        @request_sources = other.request_sources.dup
        @wrappers = other.wrappers.dup
        @schemas = other.schemas.dup
        @finalizers = other.finalizers.dup
        # A subclass may reuse its parent's names, which replaces the parent's entries in place
        @claimed = Set.new
      end

      # Records a name this class declares
      #
      # @param keyword [Symbol] declaring method (:schema, :wrapper or :security_scheme)
      # @param name [String] declared name
      # @return [void]
      # @raise [Versponse::DefinitionError] when this class already declared the name
      def claim!(keyword, name)
        raise DefinitionError, "#{keyword} #{name} is declared twice" unless @claimed.add?([keyword, name])
      end
    end
  end
end
