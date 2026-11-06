# frozen_string_literal: true

module Versponse
  # Schemas of referenced classes: Versponse classes, or any class implementing the reference
  # protocol (to_ref(property:) and to_validation_schema(version:, property:)), such as verquest requests.
  # A foreign class that references back to the class being generated (A -> verquest -> A) re-enters
  # A's schema cache and raises ThreadError; such cross-gem cycles are not supported.
  #
  # @api private
  module References
    # @param klass [Object] referenced class
    # @return [Boolean] true for Versponse response classes
    def self.versponse?(klass)
      klass.is_a?(Class) && klass < Base
    end

    # Checks a referenced Versponse class serves the version and view, so a definition mistake raises
    # DefinitionError wherever the reference compiles (serialize, schemas, eager_load!, documents)
    #
    # @param klass [Class] referenced class (anything but a Versponse class passes)
    # @param version [String] canonical version name
    # @param view [Symbol] referenced view
    # @param key [String] referencing property, for the message
    # @return [void]
    # @raise [Versponse::DefinitionError] when the class declares nothing at or before the version, or lacks the view
    # @raise [Versponse::VersionNotFoundError] when its supported_versions leave the version out (a runtime answer)
    def self.check_target!(klass, version:, view:, key:)
      return unless versponse?(klass)

      definition = target_version(klass, version, key)
      return if definition.view_names.include?(view.to_sym)

      raise DefinitionError, "#{key}: view #{view} not found in #{klass.name || "AnonymousResponse"} #{version}"
    end

    def self.target_version(klass, version, key)
      klass.versponse.resolve(version)
    rescue VersionNotFoundError
      raise if Versponse.configuration.version_resolver.call(Registry.canonical(version), klass.versponse.versions.sorted_names)

      raise DefinitionError, "#{key}: #{klass.name || "AnonymousResponse"} has no version at or before #{version}"
    end
    private_class_method :target_version

    # @param klass [Class] Versponse response class
    # @param version [String] canonical version name
    # @param view [Symbol] view to render
    # @param key [String] referencing property, for errors
    # @return [Versponse::LazyPlan] the class's plan, compiled on first use
    # @raise [Versponse::DefinitionError] see {.check_target!}
    def self.lazy_plan(klass, version:, view:, key:)
      check_target!(klass, version:, view:, key:)
      LazyPlan.new(klass, version:, view:)
    end

    # @param klass [Class] referenced class
    # @param view [Symbol] view of a Versponse class
    # @param property [Symbol, nil] property of a non-Versponse class
    # @param context [Versponse::SchemaContext] schema generation context
    # @param key [String, nil] referencing property; given, the target is checked with {.check_target!}
    # @return [Hash] a $ref, or the inlined schema in validation mode
    def self.schema(klass, view:, property:, context:, key: nil)
      return foreign_schema(klass, property:, context:) unless versponse?(klass)

      check_target!(klass, version: context.version, view:, key:) if key
      return {"$ref" => klass.to_ref(view:)} unless context.validation?

      context.inline([klass, view], klass.component_name(view:)) { klass.versponse.object_schema(version: context.version, view:, context:) }
    end

    # @param klass [Class] non-Versponse class implementing the protocol
    # @param property [Symbol, nil] referenced property
    # @param context [Versponse::SchemaContext] schema generation context
    # @return [Hash] a $ref, or its validation schema
    def self.foreign_schema(klass, property:, context:)
      return {"$ref" => klass.to_ref(property:)} unless context.validation?

      klass.to_validation_schema(version: context.version, property:)
    end

    # @param klass [Class] Versponse response class
    # @param version [String] canonical version name
    # @return [void]
    # @raise [Versponse::DefinitionError] when the class has no identifier in that version (a class that
    #   lacks the version entirely is left alone, like a plain $ref)
    def self.ensure_identifier!(klass, version)
      definition = klass.versponse.resolve(version)
    rescue VersionNotFoundError
      nil
    else
      return if definition.identifiers?

      raise DefinitionError, "#{klass.name} has no identifier in #{version}; expandable associations need one"
    end

    # @param klass [Class] Versponse response class
    # @param version [String] canonical version name
    # @return [Versponse::LazyPlan] plan of the class's collapsed view
    # @raise [Versponse::DefinitionError] when the class has no identifier
    def self.collapsed_plan(klass, version)
      ensure_identifier!(klass, version)
      LazyPlan.new(klass, version:, view: :collapsed)
    end

    # @param klass [Class] Versponse response class
    # @param version [String] canonical version name
    # @return [#call, nil] the class's identifier collapse_if in that version; nil without one or without the version
    def self.collapse_if(klass, version)
      klass.versponse.resolve(version).collapse_if
    rescue VersionNotFoundError
      nil
    end

    # @param klass [Class] Versponse response class
    # @param view [Symbol] view of the full form
    # @param context [Versponse::SchemaContext] schema generation context
    # @return [Array(Hash, Hash)] the full and the collapsed schema
    # @raise [Versponse::DefinitionError] when the class has no identifier
    def self.expandable_schemas(klass, view:, context:, key: nil)
      check_target!(klass, version: context.version, view:, key:) if key
      ensure_identifier!(klass, context.version)
      [schema(klass, view:, property: nil, context:), schema(klass, view: :collapsed, property: nil, context:)]
    end

    # @param klass [Class] referenced class
    # @param view [Symbol] view to walk
    # @param version [String] canonical version name
    # @param prefix [Array<String>] output keys leading here
    # @param stack [Array<Array(Class, Symbol)>] classes and views being walked, to stop recursion
    # @return [Array<Array<String>>] expandable paths under the class's view
    def self.nested_paths(klass, view:, version:, prefix:, stack:)
      return [] unless versponse?(klass)
      return [] if stack.include?([klass, view])

      klass.versponse.resolve(version).properties_for(view).flat_map do |property|
        property.expandable_paths(version:, prefix:, stack: [*stack, [klass, view]])
      end
    end
  end
end
