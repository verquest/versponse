# frozen_string_literal: true

module Versponse
  module OpenAPI
    # Parent of OpenAPI document classes. Declare the base, components and hooks in the class body,
    # then build one version with {.build}.
    #
    # @example
    #   class PublicApiDocument < Versponse::OpenAPI::Document
    #     document_name "public_api"
    #     versions "2025-09", "preview"
    #     info "title" => "Public API"
    #     responses namespace: "PublicApi"
    #   end
    #
    #   PublicApiDocument.build(version: "2025-09")
    class Document
      @declarations = Declarations.new

      class << self
        # @return [Versponse::OpenAPI::Declarations] this class's declarations
        # @api private
        attr_reader :declarations

        # Gives the subclass a copy of the declarations so far
        #
        # @param subclass [Class] new document class
        # @return [void]
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@declarations, declarations.dup)
        end

        # @param version [String] version to build
        # @return [Hash] String-keyed OpenAPI document
        # @raise [ArgumentError] for a version the document doesn't declare
        # @raise [Versponse::DefinitionError] for colliding component names
        def build(version:)
          Builder.new(declarations, version.to_s).call
        end

        # @param version [String] version to build and validate
        # @return [Array<Hash>] errors with :pointer, :type, :message and :details (empty when valid)
        def validate(version:)
          require "json_schemer"

          JSONSchemer.openapi(build(version:)).validate.map do |error|
            {pointer: error["data_pointer"], type: error["type"], message: error["error"], details: error["details"]}
          end
        end

        # @param value [String, Symbol, nil] the prefix to declare, nil to read it
        # @return [String, nil] the rswag key prefix
        def document_name(value = nil)
          return declarations.document_name if value.nil?

          declarations.document_name = value.to_s
        end

        # @return [Array<String>] declared versions
        def document_versions
          declarations.versions
        end

        private

        def versions(*names)
          declarations.versions = names.map(&:to_s)
        end

        def openapi(value)
          declarations.openapi = value.to_s
        end

        def info(value = nil, &block)
          declarations.info = required_value(:info, value, block)
        end

        def external_docs(value = nil, &block)
          declarations.external_docs = required_value(:external_docs, value, block)
        end

        def security(value = nil, &block)
          declarations.security = required_value(:security, value, block)
        end

        def server(url, description: nil, **extra)
          declarations.servers << {"url" => url, "description" => description}.compact.merge(extra)
        end

        def tag(name, description: nil, **extra)
          declarations.tags << {"name" => name, "description" => description}.compact.merge(extra)
        end

        def security_scheme(name, value = nil, &block)
          declarations.security_schemes[name.to_s] = required_value(:security_scheme, value, block)
        end

        def responses(classes = nil, namespace: nil)
          declarations.response_sources << source(:responses, classes, namespace)
        end

        def requests(classes = nil, namespace: nil)
          declarations.request_sources << source(:requests, classes, namespace)
        end

        def wrapper(name, klass, root:, collection: false, meta: nil, view: :default)
          declarations.wrappers << Declarations::Wrapper.new(name: name.to_s, klass:, root:, collection:, meta:, view:)
        end

        def source(keyword, classes, namespace)
          raise DefinitionError, "#{keyword} needs a list of classes or namespace:" if classes.nil? == namespace.nil?

          Declarations::Source.new(classes: classes && Array(classes), namespace: namespace&.to_s)
        end

        def finalize(&block)
          raise DefinitionError, "finalize needs a block" unless block

          declarations.finalizers << block
        end

        def required_value(keyword, value, block)
          raise DefinitionError, "#{keyword} needs a value or a block" if value.nil? && block.nil?

          block || value
        end
      end
    end
  end
end
