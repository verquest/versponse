# frozen_string_literal: true

module Versponse
  module OpenAPI
    # Finds the classes that responses and requests declarations name, and raises when they name nothing usable
    #
    # @api private
    module Sources
      # Checks an explicit list when it's declared
      #
      # @param keyword [Symbol] :responses or :requests
      # @param classes [Array<Class>] listed classes
      # @return [void]
      # @raise [Versponse::DefinitionError] for a class of the wrong kind, or a request that isn't a body request
      def self.check!(keyword, classes)
        classes.each { |klass| (keyword == :responses) ? check_response!(klass) : check_request!(klass) }
      end

      # Resolves the namespace, eager-loads it through Zeitwerk, and selects its classes
      #
      # @param keyword [Symbol] :responses or :requests
      # @param namespace [Module, String] declared namespace
      # @param kind [String] what the namespace should contain, for the error message
      # @yieldreturn [Array<Class>] loaded candidate classes, read after eager loading
      # @return [Array<Class>] the namespace's classes, sorted by name
      # @raise [Versponse::DefinitionError] when the namespace isn't defined, isn't a module, or contains no candidates
      def self.in_namespace(keyword, namespace, kind)
        mod = namespace_module(keyword, namespace)
        Zeitwerk::Loader.eager_load_namespace(mod)
        found = yield.select { |klass| klass.name&.start_with?("#{mod.name}::") }.sort_by(&:name)
        raise DefinitionError, "#{keyword} namespace: #{mod.name} matched no #{kind}" if found.empty?

        found
      end

      # @param klass [Class] verquest request
      # @return [Boolean] true for a request the document lists as a component
      def self.body?(klass)
        !klass.respond_to?(:location) || klass.location == :body
      end

      def self.check_response!(klass)
        raise DefinitionError, "responses takes Versponse::Base subclasses, got #{klass.inspect}" unless References.versponse?(klass)
      end

      def self.check_request!(klass)
        raise DefinitionError, "requests takes Verquest::Base subclasses, got #{klass.inspect}" unless verquest?(klass)
        raise DefinitionError, "requests: #{klass} is a :#{klass.location} request; only body requests are components" unless body?(klass)
      end

      def self.verquest?(klass)
        defined?(::Verquest::Base) && klass.is_a?(Class) && klass < ::Verquest::Base
      end

      def self.namespace_module(keyword, namespace)
        return namespace if namespace.is_a?(Module)

        mod = Object.const_get(namespace)
        raise DefinitionError, "#{keyword} namespace: #{namespace} is not a module" unless mod.is_a?(Module)

        mod
      rescue NameError => e
        # Only a missing segment of the path itself; a NameError raised while autoloading it is a bug to surface
        raise unless e.instance_of?(NameError) && namespace.to_s.split("::").include?(e.name.to_s)

        raise DefinitionError, "#{keyword} namespace: #{namespace} is not defined"
      end

      private_class_method :check_response!, :check_request!, :verquest?, :namespace_module
    end
  end
end
