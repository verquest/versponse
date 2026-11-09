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
    #     responses namespace: PublicApi
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

        # Validates against the OpenAPI meta-schema, and checks that every local "$ref" ("#/...") resolves,
        # which the meta-schema can't (a referenced class left out of responses, say)
        #
        # @param version [String] version to build and validate
        # @return [Array<Hash>] errors with :pointer, :type, :message and :details (empty when valid)
        def validate(version:)
          require "json_schemer"

          document = build(version:)
          errors = JSONSchemer.openapi(document).validate.map do |error|
            {pointer: error["data_pointer"], type: error["type"], message: error["error"], details: error["details"]}
          end
          errors + RefCheck.call(document)
        end

        # @param value [String, Symbol, nil] the prefix to declare, nil to read it
        # @return [String, nil] the rswag key prefix
        def document_name(value = nil)
          return declarations.document_name if value.nil?

          declarations.document_name = value.to_s
        end

        # @param names [Array<String, Symbol>] versions to declare, none to read them
        # @return [Array<String>] declared versions
        def versions(*names)
          return declarations.versions.dup if names.empty?

          declarations.versions = names.map(&:to_s)
        end

        # Alias of {versions} without arguments, kept for callers that read it under this name
        #
        # @return [Array<String>] declared versions
        def document_versions = versions

        private

        def openapi(value)
          declarations.openapi = value.to_s
        end

        def info(value = nil, &block)
          declarations.info << required_value(:info, value, block)
        end

        def external_docs(value = nil, &block)
          declarations.external_docs = required_value(:external_docs, value, block)
        end

        def security(value = nil, &block)
          declarations.security = required_value(:security, value, block)
        end

        def server(url, description: nil, **extra)
          declarations.servers << {"url" => url, "description" => description}.compact.merge(extensions(extra))
        end

        def tag(name, description: nil, **extra)
          declarations.tags << {"name" => name, "description" => description}.compact.merge(extensions(extra))
        end

        def security_scheme(name, value = nil, &block)
          value = required_value(:security_scheme, value, block)
          declarations.claim!(:security_scheme, name.to_s)
          declarations.security_schemes[name.to_s] = value
        end

        def responses(*classes, namespace: nil)
          declarations.response_sources << source(:responses, classes.flatten, namespace)
        end

        def requests(*classes, namespace: nil)
          declarations.request_sources << source(:requests, classes.flatten, namespace)
        end

        def wrapper(name, klass, root:, collection: false, meta: nil, view: :default)
          Versponse::Wrapper.check_meta!(meta)
          name = name.is_a?(Symbol) ? Naming.pascalize(name) : name.to_s
          declarations.claim!(:wrapper, name)
          declarations.wrappers[name] = Declarations::Wrapper.new(name:, klass:, root:, collection:, meta:, view:)
        end

        def schema(name, value = nil, &block)
          value = required_value(:schema, value, block)
          declarations.claim!(:schema, name.to_s)
          declarations.schemas[name.to_s] = value
        end

        def webhooks(value = nil, &block)
          declarations.webhooks = required_value(:webhooks, value, block)
        end

        def source(keyword, classes, namespace)
          raise DefinitionError, "#{keyword} needs a list of classes or namespace:" if classes.empty? == namespace.nil?
          return Declarations::Source.new(classes: nil, namespace: namespace.is_a?(Module) ? namespace : namespace.to_s) if namespace

          Sources.check!(keyword, classes)
          Declarations::Source.new(classes:, namespace: nil)
        end

        # Keyword keys that start with x_ are OpenAPI extensions: x_internal becomes "x-internal"
        def extensions(extra)
          extra.to_h { |key, value| [key.start_with?("x_") ? key.to_s.tr("_", "-") : key.to_s, value] }
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
