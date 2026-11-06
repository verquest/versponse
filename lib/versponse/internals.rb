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
      @expansions = Cache.new(limit: EXPANSION_LIMIT)
      @time_precisions = {}
      @generation = Versponse.cache_generation
    end

    # @return [Versponse::Builder] the class's DSL state and helpers
    def builder
      @builder ||= Builder.new(@klass)
    end

    # @return [String, nil] class-level description of this class or its closest ancestor that sets one
    def description
      versions.description || ancestor&.description
    end

    # @return [Hash{String => Object}] class-level schema options of this class, or of its closest ancestor that sets some
    def schema_options
      versions.schema_options.empty? ? (ancestor&.schema_options || {}) : versions.schema_options
    end

    # @return [Versponse::SupportedVersions, nil] range declared with supported_versions on this class
    #   or its closest ancestor, nil when every declared version is served
    def supported_version_range
      return @supported_version_range if defined?(@supported_version_range)

      ancestor&.supported_version_range
    end

    # @param digits [Integer] fraction digits
    # @param from [String, nil] first version it applies to
    # @return [void]
    # @raise [Versponse::DefinitionError] when the class already sets the precision from that version
    def add_time_precision(digits, from:)
      raise DefinitionError, "#{@klass.name || "AnonymousResponse"} sets time_precision #{from ? "from: #{from}" : "without from:"} twice" if @time_precisions.key?(from)

      @time_precisions = @time_precisions.merge(from => digits).freeze
    end

    # @return [Hash{String, nil => Integer}] time_precision settings of the ancestors and this class, keyed by from:
    def time_precisions
      ancestor ? ancestor.time_precisions.merge(@time_precisions) : @time_precisions
    end

    # @param version [String] canonical version name
    # @return [Hash{String => #call}] config.formatters, with the date-time formatter of the class's time_precision for the version
    def formatters(version)
      precisions = time_precisions
      from = Versponse.configuration.version_resolver.call(version, precisions.keys.compact.sort)
      precision = precisions.fetch(from) { precisions[nil] }
      return Versponse.configuration.formatters if precision.nil?

      Versponse.configuration.formatters.merge("date-time" => Formatters.date_time(precision))
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
      fresh!
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

    # Yields the canonical name of the requested version. Caches and errors work with canonical names, so a
    # VersionNotFoundError is re-raised naming what was requested.
    #
    # @param version [String, Symbol, nil] requested version, config.current_version when nil
    # @yieldparam canonical [String] canonical version name
    # @return [Object] the block's result
    # @raise [ArgumentError] without a version when config.current_version is not set
    def requesting(version)
      requested = version&.to_s || current_version_name
      canonical = Registry.canonical(requested)
      yield canonical
    rescue VersionNotFoundError => e
      raise if canonical.nil? || requested == canonical

      raise e.exception(e.message.sub("Version #{canonical} ", "Version #{requested} "))
    end

    # @param version [String] canonical (declared) version name, as serialize and nested references pass it;
    #   raw client strings would grow the cache
    # @param view [Symbol] view name
    # @return [Versponse::Plan] compiled, cached plan
    def plan(version:, view: :default)
      fresh!
      # Keyed by version, then view, so a cached lookup allocates no key Array. resolve raises for an unknown
      # version before the outer entry is stored, so client strings can't grow the cache.
      @plans.fetch(version) { resolve(version) && Cache.new }.fetch(view.to_sym) do
        definition = resolve(version)
        formatters = formatters(version)
        steps = definition.properties_for(view).map { |property| property.step(version:, formatters:) }
        Plan.new(label: "#{@klass.name}[#{definition.name}/#{view}]", steps:)
      end
    end

    # @param version [String] requested version name
    # @param view [Symbol] view name
    # @param context [Versponse::SchemaContext] schema generation context
    # @return [Hash] object schema of the version and view
    def object_schema(version:, view:, context:)
      definition = resolve(version)
      # Collapsed shapes are strict, or any object with an identifier would pass as the full one
      return ObjectSchema.build(definition.properties_for(:collapsed), context, additional_properties: false) if view.to_sym == :collapsed

      ObjectSchema.build(definition.properties_for(view), context, description: definition.description, schema_options: definition.schema_options)
    end

    # @param version [String] canonical version name
    # @param view [Symbol] view name
    # @return [Hash] frozen OpenAPI schema
    def openapi_schema(version:, view:)
      fresh!
      @schemas.fetch([:openapi, version, view.to_sym]) do
        finished(object_schema(version:, view:, context: SchemaContext.new(version:, validation: false)))
      end
    end

    # @param version [String] canonical version name
    # @param view [Symbol] view name
    # @return [Hash] frozen schema with every reference inlined
    def validation_schema(version:, view:)
      fresh!
      @schemas.fetch([:validation, version, view.to_sym]) do
        context = SchemaContext.new(version:, validation: true)
        finished(context.inline([@klass, view.to_sym], @klass.component_name(view:)) { object_schema(version:, view:, context:) })
      end
    end

    # @param version [String] canonical version name
    # @param view [Symbol] view name
    # @param key [String] property key
    # @return [Hash] frozen validation schema of one property
    # @raise [Versponse::PropertyNotFoundError] for an unknown property
    def property_validation_schema(version:, view:, key:)
      fresh!
      @schemas.fetch([:validation, version, view.to_sym, key]) do
        target = resolve(version).properties_for(view).find { |property| property.key == key } ||
          raise(PropertyNotFoundError, "Property #{key} not found in #{@klass.name} #{version}/#{view}")
        finished(target.schema(SchemaContext.new(version:, validation: true)))
      end
    end

    # @param version [String] canonical (declared) version name
    # @param view [Symbol] view name
    # @return [JSONSchemer::Schema] compiled, cached validation schema
    def schemer(version:, view: :default)
      fresh!
      @schemers.fetch([version, view.to_sym]) do
        require "json_schemer"
        JSONSchemer.schema(validation_schema(version:, view:), meta_schema: Versponse.configuration.json_schema_uri)
      end
    end

    # @param version [String] canonical (declared) version name
    # @param view [Symbol] view name
    # @return [#valid?, nil] fast checker compiled from the validation schema, nil when it uses keywords the compiler does not support
    def checker(version:, view: :default)
      fresh!
      @checkers.fetch([version, view.to_sym]) do
        Validator::Compiler.call(validation_schema(version:, view:), schemer(version:, view:))
      end
    end

    # @param version [String] canonical version name
    # @param view [Symbol] view name
    # @return [Array<String>] sorted, frozen expandable paths
    def expandable_paths(version:, view:)
      fresh!
      @expandable_paths.fetch([version, view.to_sym]) do
        References.nested_paths(@klass, view: view.to_sym, version:, prefix: [], stack: []).map { |path| path.join(".") }.uniq.sort.freeze
      end
    end

    # Trees are cached by their sorted paths, up to {EXPANSION_LIMIT} combinations. A list with unknown paths
    # (config.unknown_expand = :ignore) is cached under its valid paths only, so junk can't take the slots.
    #
    # @param expand [Array<String, Symbol>, String, Symbol, nil] requested paths: dotted, "*", or ending in ".*"
    # @param version [String] canonical version name
    # @param view [Symbol] view name
    # @return [Versponse::Expansion] the expand tree
    # @raise [Versponse::InvalidExpandError] for unknown paths (config.unknown_expand = :raise)
    def expansion(expand, version:, view:)
      return Expansion::NONE if expand.nil?

      fresh!
      paths = Array(expand).map(&:to_s).uniq
      return Expansion::NONE if paths.empty?

      @expansions[[version, view.to_sym, paths.sort]] || validated_expansion(paths, version:, view:)
    end

    # Checks without compiling that every referenced class serves the version and view, in every view,
    # so eager_load! catches nested mistakes at versions the class serves but doesn't declare
    #
    # @param version [String] canonical version name
    # @return [void]
    # @raise [Versponse::DefinitionError] see {References.check_target!}
    # @raise [Versponse::VersionNotFoundError] when the class (or a referenced class's range) doesn't serve the version
    def check_references!(version)
      definition = resolve(version)
      definition.view_names.each do |view|
        definition.properties_for(view).flat_map(&:reference_targets).each do |klass, target_view, key|
          References.check_target!(klass, version:, view: target_view, key:)
        end
      end
    end

    private

    # Version-specific rewrites of a generated schema, then a frozen copy
    def finished(schema)
      DeepFreeze.call(Versponse.configuration.const_keyword? ? schema : ConstAsEnum.call(schema))
    end

    def ancestor
      superclass = @klass.superclass
      superclass.versponse if superclass < Base
    end

    # Versponse.reset_caches! bumps a global generation instead of walking every class; each class clears
    # its own caches on next use. One Integer comparison per call.
    def fresh!
      generation = Versponse.cache_generation
      return if @generation == generation

      # New objects, not clear: a compile in flight on this thread holds the old caches' locks,
      # and finishes into the discarded cache
      @plans = Cache.new
      @schemas = Cache.new
      @schemers = Cache.new
      @checkers = Cache.new
      @expandable_paths = Cache.new
      @expansions = Cache.new(limit: EXPANSION_LIMIT)
      versions.clear_resolved
      @generation = generation
    end

    def current_version_name
      current = Versponse.configuration.current_version
      raise ArgumentError, "version: is required when config.current_version is not set" unless current

      value = current.call
      raise ArgumentError, "config.current_version returned nil" if value.nil?

      value.to_s
    end

    def validated_expansion(paths, version:, view:)
      valid, unknown = paths.partition { |path| known_path?(path, version:, view:) }
      raise InvalidExpandError.new(paths: unknown) if unknown.any? && Versponse.configuration.unknown_expand == :raise
      return Expansion::NONE if valid.empty?

      @expansions.fetch([version, view.to_sym, valid.sort]) do
        Expansion.build(valid.flat_map { |path| expanded_paths(path, version:, view:) })
      end
    end

    # "*" is always known; "<path>.*" when the path is expandable or has expandable paths below it
    def known_path?(path, version:, view:)
      return true if path == "*"

      base = path.delete_suffix(".*")
      return false if base.split(".", -1).include?("")
      return true if expandable_path?(base, version:, view:)

      base != path && expandable_paths(version:, view:).any? { |known| known.start_with?("#{base}.") }
    end

    # "*" expands every path expandable_paths lists, so each recursive association expands once and cyclic
    # object graphs can't recurse forever; "<path>.*" is the path (when expandable) and every listed path below it
    def expanded_paths(path, version:, view:)
      return expandable_paths(version:, view:) if path == "*"
      return [path] unless path.end_with?(".*")

      base = path.delete_suffix(".*")
      below = expandable_paths(version:, view:).select { |known| known.start_with?("#{base}.") }
      expandable_path?(base, version:, view:) ? [base, *below] : below
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
