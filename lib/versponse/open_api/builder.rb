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

      # @return [Hash] the document
      # @raise [ArgumentError] for a version the document doesn't declare
      # @raise [Versponse::DefinitionError] for colliding component names
      def call
        check_version!
        document = base.merge("components" => components)
        @declarations.finalizers.each { |hook| hook.call(document, @version) }
        document
      end

      private

      def check_version!
        versions = @declarations.versions
        return if versions.empty? || versions.include?(@version)

        raise ArgumentError, "#{@version} is not a version of this document (#{versions.join(", ")})"
      end

      def base
        {
          "openapi" => @declarations.openapi,
          "info" => {"version" => @version}.merge(resolve(@declarations.info) || {}),
          "externalDocs" => resolve(@declarations.external_docs),
          "servers" => presence(resolve(@declarations.servers)),
          "tags" => presence(resolve(@declarations.tags)),
          "security" => resolve(@declarations.security),
          "paths" => {}
        }.compact
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
        set.to_h
      end

      def add_responses(set)
        response_classes.each do |klass|
          Versponse.components(version: @version, classes: [klass]).each { |name, schema| set.add(name, schema, klass.name) }
        end
      end

      def add_requests(set)
        request_classes.each do |klass|
          schema = request_schema(klass)
          set.add(klass.component_name, schema, klass.name) if schema
        end
      end

      def add_wrappers(set)
        @declarations.wrappers.each do |wrapper|
          schema = wrapper.klass.to_schema(version: @version, view: wrapper.view, root: wrapper.root, meta: wrapper.meta, collection: wrapper.collection)
          set.add(wrapper.name, schema, "wrapper #{wrapper.name}")
        end
      end

      def response_classes
        select(@declarations.response_sources) { Registry.classes }
      end

      def request_classes
        select(@declarations.request_sources) { verquest_classes }.select { |klass| !klass.respond_to?(:location) || klass.location == :body }
      end

      def select(sources, &candidates)
        sources.flat_map do |source|
          next source.classes if source.classes

          candidates.call.select { |klass| klass.name&.start_with?("#{source.namespace}::") }.sort_by(&:name)
        end.uniq
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

      def resolve(value)
        Values.resolve(value, @version)
      end
    end
  end
end
