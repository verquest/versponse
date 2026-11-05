# frozen_string_literal: true

module Versponse
  module OpenAPI
    # Everything a document class declares. Subclasses get a copy, so they inherit and extend it.
    #
    # @api private
    class Declarations
      # One response or request source: an explicit list or a namespace
      Source = Data.define(:classes, :namespace)
      # One named wrapper component
      Wrapper = Data.define(:name, :klass, :root, :collection, :meta, :view)

      # @return [String, nil] rswag key prefix
      attr_accessor :document_name
      # @return [String] openapi field
      attr_accessor :openapi
      # @return [Hash, Proc, nil] info
      attr_accessor :info
      # @return [Hash, Proc, nil] externalDocs
      attr_accessor :external_docs
      # @return [Array, Proc, nil] top-level security
      attr_accessor :security
      # @return [Array<String>] versions exposed to rswag (empty = any version)
      attr_accessor :versions
      # @return [Array<Hash>] servers
      attr_reader :servers
      # @return [Array<Hash>] tags
      attr_reader :tags
      # @return [Hash{String => Hash, Proc}] securitySchemes
      attr_reader :security_schemes
      # @return [Array<Source>] response sources
      attr_reader :response_sources
      # @return [Array<Source>] request sources
      attr_reader :request_sources
      # @return [Array<Wrapper>] wrapper components
      attr_reader :wrappers
      # @return [Array<Proc>] finalize hooks
      attr_reader :finalizers

      # @return [Declarations] empty declarations with openapi "3.1.1"
      def initialize
        @openapi = "3.1.1"
        @versions = []
        @servers = []
        @tags = []
        @security_schemes = {}
        @response_sources = []
        @request_sources = []
        @wrappers = []
        @finalizers = []
      end

      # @param other [Declarations] declarations being copied
      # @return [void]
      def initialize_copy(other)
        super
        @versions = other.versions.dup
        @servers = other.servers.dup
        @tags = other.tags.dup
        @security_schemes = other.security_schemes.dup
        @response_sources = other.response_sources.dup
        @request_sources = other.request_sources.dup
        @wrappers = other.wrappers.dup
        @finalizers = other.finalizers.dup
      end
    end
  end
end
