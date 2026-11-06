# frozen_string_literal: true

module Versponse
  # Per-class state and compilation of a response class: its versions, resolution and caches.
  # Kept off the class itself (reached through {Base::ClassMethods#versponse}), so the class
  # exposes only the documented API and a user's own class methods can't clash with it.
  #
  # @api private
  class Internals
    # Most expand: combinations cached per class; they come from requests, so further ones are rebuilt each time
    EXPANSION_LIMIT = 256

    # @return [Versponse::Versions] declared versions
    attr_reader :versions
    # @return [Versponse::SupportedVersions, nil] range declared with supported_versions, nil to remove an inherited one
    attr_writer :supported_version_range

    # @param klass [Class] response class
    def initialize(klass)
      @klass = klass
      @versions = Versions.new(owner: klass.name || "AnonymousResponse")
      @plans = Cache.new
      @schemas = Cache.new
      @schemers = Cache.new
      @checkers = Cache.new
      @expandable_paths = Cache.new
      @wildcards = Cache.new
      @expansions = Cache.new(limit: EXPANSION_LIMIT)
    end

    # @return [Versponse::SupportedVersions, nil] range declared with supported_versions on this class
    #   or its closest ancestor, nil when every declared version is served
    def supported_version_range
      return @supported_version_range if defined?(@supported_version_range)

      superclass = @klass.superclass
      superclass.versponse.supported_version_range if superclass < Base
    end

    # Names that resolve within supported_versions: the declared versions in range plus min,
    # so a min: "preview" class whose only block is 2025-09 compiles that block as "preview"
    #
    # @return [Array<String>] canonical version names; every declared version without a range
    # @raise [Versponse::DefinitionError] when supported_versions max sorts before every declared version
    def supported_version_names
      versions.supported_names(supported_version_range)
    end

    # @param version [String] requested version
    # @return [Versponse::Version] closest declared version at or before it
    # @raise [Versponse::VersionNotFoundError] when there is none, or supported_versions leaves it out
    # @raise [Versponse::DefinitionError] when supported_versions max sorts before every declared version
    def resolve(version)
      versions.resolve(Registry.canonical(version.to_s), supported: supported_version_range)
    end

    # Maps the requested version to a registered name before it reaches a cache (see Registry.canonical).
    # Assumes the resolver picks the closest earlier version, like the default one.
    #
    # @param version [String, Symbol, nil] requested version, config.current_version when nil
    # @return [String] canonical version name
    # @raise [ArgumentError] without a version when config.current_version is not set
    def version_name(version)
      Registry.canonical(version&.to_s || current_version_name)
    end

    # @param version [String] canonical (declared) version name, as serialize and nested references pass it;
    #   raw client strings would grow the cache
    # @param view [Symbol] view name
    # @return [Versponse::Plan] compiled, cached plan
    def plan(version:, view: :default)
      # Keyed by version, then view, so a cached lookup allocates no key Array
      @plans.fetch(version) { Cache.new }.fetch(view.to_sym) do
        definition = resolve(version)
        steps = definition.properties_for(view).map { |property| property.step(version:) }
        Plan.new(label: "#{@klass.name}[#{definition.name}/#{view}]", steps:)
      end
    end

    # @param version [String] requested version name
    # @param view [Symbol] view name
    # @param context [Versponse::SchemaContext] schema generation context
    # @return [Hash] object schema of the version and view
    def object_schema(version:, view:, context:)
      definition = resolve(version)
      return ObjectSchema.build(definition.properties_for(:collapsed), context) if view.to_sym == :collapsed

      ObjectSchema.build(definition.properties_for(view), context, description: definition.description, schema_options: definition.schema_options)
    end

    # @param version [String] canonical version name
    # @param view [Symbol] view name
    # @return [Hash] frozen OpenAPI schema
    def openapi_schema(version:, view:)
      @schemas.fetch([:openapi, version, view.to_sym]) do
        DeepFreeze.call(object_schema(version:, view:, context: SchemaContext.new(version:, validation: false)))
      end
    end

    # @param version [String] canonical version name
    # @param view [Symbol] view name
    # @return [Hash] frozen schema with every reference inlined
    def validation_schema(version:, view:)
      @schemas.fetch([:validation, version, view.to_sym]) do
        context = SchemaContext.new(version:, validation: true)
        DeepFreeze.call(context.inline([@klass, view.to_sym], @klass.component_name(view:)) { object_schema(version:, view:, context:) })
      end
    end

    # @param version [String] canonical version name
    # @param view [Symbol] view name
    # @param key [String] property key
    # @return [Hash] frozen validation schema of one property
    # @raise [Versponse::PropertyNotFoundError] for an unknown property
    def property_validation_schema(version:, view:, key:)
      @schemas.fetch([:validation, version, view.to_sym, key]) do
        target = resolve(version).properties_for(view).find { |property| property.key == key } ||
          raise(PropertyNotFoundError, "Property #{key} not found in #{@klass.name} #{version}/#{view}")
        DeepFreeze.call(target.schema(SchemaContext.new(version:, validation: true)))
      end
    end

    # @param version [String] canonical (declared) version name
    # @param view [Symbol] view name
    # @return [JSONSchemer::Schema] compiled, cached validation schema
    def schemer(version:, view: :default)
      @schemers.fetch([version, view.to_sym]) do
        require "json_schemer"
        JSONSchemer.schema(validation_schema(version:, view:), meta_schema: Versponse.configuration.json_schema_uri)
      end
    end

    # @param version [String] canonical (declared) version name
    # @param view [Symbol] view name
    # @return [#valid?, nil] fast checker compiled from the validation schema, nil when it uses keywords the compiler does not support
    def checker(version:, view: :default)
      @checkers.fetch([version, view.to_sym]) do
        Validator::Compiler.call(validation_schema(version:, view:), schemer(version:, view:))
      end
    end

    # @param version [String] canonical version name
    # @param view [Symbol] view name
    # @return [Array<String>] sorted, frozen expandable paths
    def expandable_paths(version:, view:)
      @expandable_paths.fetch([version, view.to_sym]) do
        References.nested_paths(@klass, view: view.to_sym, version:, prefix: [], stack: []).map { |path| path.join(".") }.uniq.sort.freeze
      end
    end

    # Validated trees are cached by their sorted paths, up to {EXPANSION_LIMIT} combinations
    #
    # @param expand [Array<String, Symbol>, String, Symbol, nil] requested paths: dotted, "*", or ending in ".*"
    # @param version [String] canonical version name
    # @param view [Symbol] view name
    # @return [Versponse::Expansion] the expand tree
    # @raise [Versponse::InvalidExpandError] for unknown paths (config.unknown_expand = :raise)
    def expansion(expand, version:, view:)
      return Expansion::NONE if expand.nil?

      paths = Array(expand).map(&:to_s).uniq
      return Expansion::NONE if paths.empty?
      return wildcard_expansion(version:, view:) if paths.include?("*")

      @expansions.fetch([version, view.to_sym, Versponse.configuration.unknown_expand, paths.sort]) do
        build_expansion(paths, version:, view:)
      end
    end

    # Clears compiled plans, schemas, schemers, checkers and resolved versions
    #
    # @return [void]
    def reset_caches!
      [@plans, @schemas, @schemers, @checkers, @expandable_paths, @wildcards].each(&:clear)
      versions.clear_resolved
    end

    private

    def current_version_name
      current = Versponse.configuration.current_version
      raise ArgumentError, "version: is required when config.current_version is not set" unless current

      current.call.to_s
    end

    def build_expansion(paths, version:, view:)
      unknown = paths.reject { |path| expandable_path?(path.delete_suffix(".*"), version:, view:) }
      raise InvalidExpandError.new(paths: unknown) if unknown.any? && Versponse.configuration.unknown_expand == :raise

      Expansion.build((paths - unknown).flat_map { |path| with_wildcards(path, version:, view:) })
    end

    # "<path>.*" is the path plus every expandable path below it
    def with_wildcards(path, version:, view:)
      return [path] unless path.end_with?(".*")

      prefix = path.delete_suffix(".*")
      [prefix, *expandable_paths(version:, view:).select { |known| known.start_with?("#{prefix}.") }]
    end

    # "*" expands every path expandable_paths lists, so each recursive association expands once
    # and cyclic object graphs can't recurse forever
    def wildcard_expansion(version:, view:)
      @wildcards.fetch([version, view.to_sym]) do
        Expansion.build(expandable_paths(version:, view:))
      end
    end

    # Walks the requested path one segment at a time; valid when the last segment is expandable.
    # Every property with a matching key is tried, because one_of variants can share keys.
    def expandable_path?(path, version:, view:)
      path_known?(resolve(version).properties_for(view), path.split("."), version)
    end

    def path_known?(properties, segments, version)
      head, *rest = segments
      properties.select { |property| property.key == head }.any? do |property|
        target = property.path_target(version)
        rest.empty? ? target.expandable_path? : path_known?(target.path_children(version), rest, version)
      end
    end
  end
end
