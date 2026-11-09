# frozen_string_literal: true

module Versponse
  module OpenAPI
    # Assembles one version of a document into a String-keyed Hash
    #
    # @api private
    class Builder
      # @param declarations [Versponse::OpenAPI::Declarations] the document's declarations
      # @param version [String] version to build
      def initialize(declarations, version)
        @declarations = declarations
        @version = version
      end

      # @return [Hash] the document, a copy the caller can change
      # @raise [ArgumentError] for a version the document doesn't declare
      # @raise [Versponse::DefinitionError] for colliding component names, an openapi version config.json_schema_version
      #   doesn't write, or webhooks in an OpenAPI 3.0 document
      def call
        check_version!
        # Components are the classes' frozen, cached schemas, so the caller and the hooks get a copy
        document = DeepCopy.call(base.merge("components" => components))
        # A hook that takes one argument gets only the document
        @declarations.finalizers.each { |hook| (hook.arity == 1) ? hook.call(document) : hook.call(document, @version) }
        document
      end

      private

      def check_version!
        versions = @declarations.versions
        return if versions.empty? || versions.include?(@version)

        raise ArgumentError, "#{@version} is not a version of this document (#{versions.join(", ")})"
      end

      def base
        openapi = openapi_version
        webhooks = resolve(@declarations.webhooks)
        if webhooks && openapi.start_with?("3.0.")
          raise DefinitionError, "webhooks need OpenAPI 3.1 (config.json_schema_version is :#{Versponse.configuration.json_schema_version})"
        end

        {
          "openapi" => openapi,
          "info" => info,
          "externalDocs" => resolve(@declarations.external_docs),
          "servers" => presence(resolve(@declarations.servers)),
          "tags" => presence(resolve(@declarations.tags)),
          "security" => resolve(@declarations.security),
          "paths" => {},
          "webhooks" => webhooks
        }.compact
      end

      # Each layer is resolved for the version and merged over the ones before it
      def info
        @declarations.info.reduce({"version" => @version}) { |merged, layer| merged.merge(resolve(layer) || {}) }
      end

      def components
        schemes = @declarations.security_schemes.transform_values { |scheme| resolve(scheme) }
        {"securitySchemes" => presence(schemes), "schemas" => schemas}.compact
      end

      def schemas
        set = ComponentSet.new
        add_responses(set)
        add_requests(set)
        add_wrappers(set)
        add_schemas(set)
        set.to_h
      end

      def add_responses(set)
        response_classes.each do |klass|
          Versponse.components(version: @version, classes: [klass]).each { |name, schema| set.add(name, schema, klass.name) }
        end
      end

      def add_requests(set)
        request_classes.each do |klass|
          References.check_dialect!(klass)
          schema = request_schema(klass)
          set.add(klass.component_name, schema, klass.name) if schema
        end
      end

      # Wrapper schemas only $ref the class, so skip classes that don't cover the version (supported_versions)
      def add_wrappers(set)
        @declarations.wrappers.each_value do |wrapper|
          next unless Components.resolved(wrapper.klass, @version)

          schema = wrapper.klass.to_schema(version: @version, view: wrapper.view, root: wrapper.root, meta: wrapper.meta, collection: wrapper.collection)
          set.add(wrapper.name, schema, "wrapper #{wrapper.name}")
        end
      end

      # Hand-written components are schemas, so they're camelized like every other schema; other document values aren't
      def add_schemas(set)
        @declarations.schemas.each do |name, value|
          value = resolve(value)
          set.add(name, value.is_a?(Hash) ? Naming.camelize_keys(value) : value, "schema #{name}")
        end
      end

      def response_classes
        select(@declarations.response_sources, :responses, "response classes") { Registry.classes }
      end

      def request_classes
        select(@declarations.request_sources, :requests, "body requests") { verquest_classes.select { |klass| Sources.body?(klass) } }
      end

      def select(sources, keyword, kind, &candidates)
        sources.flat_map { |source| source.classes || Sources.in_namespace(keyword, source.namespace, kind, &candidates) }.uniq
      end

      def verquest_classes
        raise DefinitionError, "requests namespace: needs verquest to be loaded" unless defined?(::Verquest::Base)

        descendants(::Verquest::Base)
      end

      def descendants(klass)
        klass.subclasses.flat_map { |subclass| [subclass, *descendants(subclass)] }
      end

      def request_schema(klass)
        klass.to_schema(version: @version)
      rescue *version_errors
        nil
      end

      def version_errors
        [VersionNotFoundError, (::Verquest::VersionNotFoundError if defined?(::Verquest::VersionNotFoundError))].compact
      end

      def presence(collection)
        collection unless collection.empty?
      end

      # Schemas are written for config.json_schema_version, so the document declares the matching version
      def openapi_version
        openapi30 = Versponse.configuration.json_schema_version == :openapi30
        declared = @declarations.openapi
        return openapi30 ? "3.0.3" : "3.1.1" if declared.nil?
        return declared if declared.start_with?("3.0.") == openapi30

        raise DefinitionError, "openapi #{declared} doesn't match config.json_schema_version :#{Versponse.configuration.json_schema_version} (use #{openapi30 ? "3.0.x" : "3.1.x"})"
      end

      def resolve(value)
        Values.resolve(value, @version)
      end
    end
  end
end
