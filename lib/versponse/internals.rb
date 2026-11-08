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

    # Most fields: combinations cached per class (checked paths, pruned validation schemas)
    SELECTION_LIMIT = 64

    # @return [Versponse::Versions] declared versions
    attr_reader :versions
    # @return [Versponse::SupportedVersions, nil] range declared with supported_versions, nil to remove an inherited one
    attr_writer :supported_version_range
    # @return [#call, nil] on_nil declared on this class, nil to remove an inherited one
    attr_writer :on_nil
    # @return [Symbol, #call, nil] on_error declared on this class, nil to remove an inherited one
    attr_writer :on_error

    # @param klass [Class] response class
    def initialize(klass)
      @klass = klass
      @versions = Versions.new(owner: klass.name || "AnonymousResponse")
      @plans = Cache.new
      @schemas = Cache.new
      @schemers = Cache.new
      @checkers = Cache.new
      @validating_plans = Cache.new
      @expandable_paths = Cache.new
      @expandable_targets = Cache.new
      @selectable_paths = Cache.new
      @expansions = Cache.new(limit: EXPANSION_LIMIT)
      @raw_expansions = Cache.new
      @field_paths = Cache.new(limit: SELECTION_LIMIT)
      @selected_validators = Cache.new(limit: SELECTION_LIMIT)
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

    # Looked up when schemas are built, so declaration order of parent and subclass doesn't matter
    #
    # @return [Hash{String => Object}] class-level schema options of the ancestors merged with this class's own
    def schema_options
      (ancestor&.schema_options || {}).merge(versions.schema_options)
    end

    # @return [Versponse::SupportedVersions, nil] range declared with supported_versions on this class
    #   or its closest ancestor, nil when every declared version is served
    def supported_version_range
      return @supported_version_range if defined?(@supported_version_range)

      ancestor&.supported_version_range
    end

    # @return [#call, nil] on_nil of this class or its closest ancestor that sets one
    def on_nil
      return @on_nil if defined?(@on_nil)

      ancestor&.on_nil
    end

    # @return [Symbol, #call, nil] on_error of this class or its closest ancestor that sets one
    def on_error
      return @on_error if defined?(@on_error)

      ancestor&.on_error
    end

    # @return [Versponse::ClassPolicies] class settings for compiling the class's steps
    def policies
      ClassPolicies.new(response: @klass, on_nil:, on_error:)
    end

    # @param digits [Integer] fraction digits
    # @param from [String, nil] first version it applies to
    # @return [void]
    # @raise [Versponse::DefinitionError] when the class already sets the precision from that version
    def add_time_precision(digits, from:)
      raise DefinitionError, "#{@klass.name || "AnonymousResponse"} sets time_precision #{from ? "from: #{from}" : "without from:"} twice" if @time_precisions.key?(from)

      @time_precisions = @time_precisions.merge(from => digits).freeze
    end

    # A class that sets any time_precision uses only its own settings; one that sets none inherits the
    # closest ancestor's, so two classes' timelines never mix
    #
    # @return [Hash{String, nil => Integer}] time_precision settings, keyed by from:
    def time_precisions
      return @time_precisions unless @time_precisions.empty?

      ancestor&.time_precisions || @time_precisions
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
      compiled = @plans[version]&.[](view)
      return compiled if compiled

      # Keyed by version, then view, so a cached lookup allocates no key Array. resolve raises for an unknown
      # version before the outer entry is stored, so client strings can't grow the cache.
      @plans.fetch(version) { resolve(version) && Cache.new }.fetch(view.to_sym) do
        definition = resolve(version)
        formatters = formatters(version)
        policies = self.policies
        properties = definition.properties_for(view)
        steps = properties.map { |property| property.step(version:, formatters:, policies:) }
        Plan.new(label: "#{@klass.name}[#{definition.name}/#{view}]", steps:, recoveries: ErrorPolicy.recoveries(properties, policies, version),
          always: definition.identifiers.keys)
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

      # Class-level settings are looked up now (live); the version's own win
      ObjectSchema.build(definition.properties_for(view), context, description: definition.description || description,
        schema_options: schema_options.merge(definition.schema_options))
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
      compiled = @checkers[version]&.[](view)
      return compiled if compiled

      # Keyed by version, then view, like plan, so a hit allocates no key Array; a nil checker (unsupported
      # schema) misses the line above and is found by the nested fetch, which allocates nothing either
      @checkers.fetch(version) { resolve(version) && Cache.new }.fetch(view.to_sym) do
        Validator::Compiler.call(validation_schema(version:, view:), schemer(version:, view:))
      end
    end

    # @param version [String] canonical version name
    # @param view [Symbol] view name
    # @param selection [Versponse::Selection] a root selection (not ALL)
    # @return [Array(#valid?, JSONSchemer::Schema)] compiled checker (nil when unsupported) and json_schemer schema of
    #   the validation schema pruned for the selection, cached by its signature
    def selected_validators(version:, view:, selection:)
      fresh!
      @selected_validators.fetch([version, view.to_sym, selection.signature]) do
        require "json_schemer"
        schema = DeepFreeze.call(SelectionSchema.call(validation_schema(version:, view:), selection))
        schemer = JSONSchemer.schema(schema, meta_schema: Versponse.configuration.json_schema_uri)
        [Validator::Compiler.call(schema, schemer), schemer].freeze
      end
    end

    # @param version [String] canonical (declared) version name
    # @param view [Symbol] view name
    # @return [Versponse::Plan, nil] plan that validates while rendering (see {InlineValidation::Builder}), nil when
    #   the validation schema doesn't prove one
    def validating_plan(version:, view: :default)
      fresh!
      view = view.to_sym
      cache = @validating_plans
      cached = cache[version]&.[](view)
      return (cached unless UNPROVEN.equal?(cached)) if cached

      # Built outside the cache lock, so it never holds this class's lock while reading other classes' plans (a
      # duplicate build in a race is harmless); stored into the cache read above, so a reset meanwhile discards it
      built = build_validating_plan(version:, view:) || UNPROVEN
      stored = cache.fetch(version) { resolve(version) && Cache.new }.fetch(view) { built }
      stored unless UNPROVEN.equal?(stored)
    end

    # @param version [String] canonical version name
    # @param view [Symbol] view name
    # @return [Array<String>] sorted, frozen expandable paths
    def expandable_paths(version:, view:)
      fresh!
      @expandable_paths.fetch([version, view.to_sym]) do
        expandable_entries(version, view).map { |path, _classes| path.join(".") }.uniq.sort.freeze
      end
    end

    # @param version [String] canonical version name
    # @param view [Symbol] view name
    # @return [Hash{String => Array<Class>}] frozen, keyed by the sorted expandable paths; each value lists the
    #   classes the path renders, in declaration order
    def expandable_targets(version:, view:)
      fresh!
      @expandable_targets.fetch([version, view.to_sym]) do
        targets = Hash.new { |hash, path| hash[path] = [] }
        expandable_entries(version, view).each { |path, classes| targets[path.join(".")] |= classes }
        targets.sort.to_h { |path, classes| [path, classes.freeze] }.freeze
      end
    end

    # @param version [String] canonical version name
    # @param view [Symbol] view name
    # @return [Array<String>] sorted, frozen paths fields: accepts (without wildcards)
    def selectable_paths(version:, view:)
      fresh!
      @selectable_paths.fetch([version, view.to_sym]) do
        paths = []
        collect_field_paths(resolve(version).properties_for(view), [], version, [], paths)
        paths.uniq.sort.freeze
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
      raw = @raw_expansions[version]&.[](view)&.[](expand)
      return raw if raw

      paths = Array(expand).map(&:to_s).uniq
      return Expansion::NONE if paths.empty?

      tree = @expansions[[version, view.to_sym, paths.sort]]
      return remember_expansion(expand, tree, version:, view:) if tree

      validated_expansion(paths, version:, view:) { |known| remember_expansion(expand, known, version:, view:) }
    end

    # @param fields [Array<String, Symbol>, nil] requested paths: dotted, "*", or ending in ".*"
    # @param version [String] canonical version name
    # @param view [Symbol] view name
    # @param expansion [Versponse::Expansion] the render's expand tree
    # @return [Versponse::Selection] the selection, ALL for no paths
    # @raise [Versponse::InvalidFieldsError] for unknown paths and paths below unexpanded associations
    #   (config.unknown_fields = :raise)
    def selection(fields, version:, view:, expansion:)
      return Selection::ALL if fields.nil?

      paths = Array(fields).map(&:to_s).uniq
      return Selection::ALL if paths.empty? || paths.include?("*")

      fresh!
      # The checked selection is cached with its step-index memo; expansions are cached trees, so the same expand:
      # gives the same key
      selection, reasons = @field_paths.fetch([version, view.to_sym, paths.sort, expansion]) do
        problems = paths.to_h { |path| [path, field_path_problem(path, version:, view:, expansion:)] }.compact
        [Selection.build(paths - problems.keys), problems.freeze].freeze
      end
      raise InvalidFieldsError.new(paths: reasons.keys, reasons:) if reasons.any? && Versponse.configuration.unknown_fields == :raise

      selection
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

    def expandable_entries(version, view)
      References.nested_entries(@klass, view: view.to_sym, version:, prefix: [], stack: [])
    end

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
      @validating_plans = Cache.new
      @expandable_paths = Cache.new
      @expandable_targets = Cache.new
      @selectable_paths = Cache.new
      @expansions = Cache.new(limit: EXPANSION_LIMIT)
      @raw_expansions = Cache.new
      @field_paths = Cache.new(limit: SELECTION_LIMIT)
      @selected_validators = Cache.new(limit: SELECTION_LIMIT)
      versions.clear_resolved
      @generation = generation
    end

    # Stored for a class/view without a validating plan, so it isn't rebuilt on every render
    UNPROVEN = Object.new.freeze
    private_constant :UNPROVEN

    # Compiles the validation schema once for both: the root checker goes into the checker cache read before the
    # build (a reset meanwhile discards it), and the compiler's subschema checkers prove the plan
    def build_validating_plan(version:, view:)
      checkers = @checkers
      schema = validation_schema(version:, view:)
      compiler = Validator::Compiler.new(schemer(version:, view:))
      root = begin
        compiler.root(schema)
      rescue Validator::Compiler::Unsupported
        nil
      end
      checkers.fetch(version) { resolve(version) && Cache.new }.fetch(view) { root }
      InlineValidation::Builder.new(compiler).prove(plan(version:, view:), schema) if root
    end

    def current_version_name
      current = Versponse.configuration.current_version
      raise ArgumentError, "version: is required when config.current_version is not set" unless current

      value = current.call
      raise ArgumentError, "config.current_version returned nil" if value.nil?

      value.to_s
    end

    # Yields the tree when every path is known, so the requested value can be remembered as a key
    def validated_expansion(paths, version:, view:)
      valid, unknown = paths.partition { |path| known_path?(path, version:, view:) }
      raise InvalidExpandError.new(paths: unknown) if unknown.any? && Versponse.configuration.unknown_expand == :raise
      return Expansion::NONE if valid.empty?

      tree = @expansions.fetch([version, view.to_sym, valid.sort]) do
        Expansion.build(valid.flat_map { |path| expanded_paths(path, version:, view:) })
      end
      unknown.empty? ? yield(tree) : tree
    end

    # Stores the tree under the requested value as given (an Array as a frozen copy), so a repeated
    # expand: is found without normalizing or allocating. Only lists whose paths are all known get here.
    def remember_expansion(expand, tree, version:, view:)
      key = (expand.is_a?(::Array) && !expand.frozen?) ? expand.dup.freeze : expand
      by_view = @raw_expansions.fetch(version) { Cache.new }
      by_view.fetch(view) { Cache.new(limit: EXPANSION_LIMIT) }.fetch(key) { tree }
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

    # nil for a valid path, else why it isn't
    def field_path_problem(path, version:, view:, expansion:)
      segments = path.delete_suffix(".*").split(".", -1)
      return "unknown" if segments.empty? || segments.include?("") || segments.include?("*")

      field_walk(resolve(version).properties_for(view), segments, version, expansion, [])
    end

    # Every property with a matching key is tried, because one_of variants can share keys
    def field_walk(properties, segments, version, expansion, walked)
      head, *rest = segments
      candidates = properties.select { |property| property.key == head }
      return "unknown" if candidates.empty?
      return if rest.empty?

      problems = candidates.map do |property|
        target = property.path_target(version)
        next "#{[*walked, head].join(".")} isn't expanded" if target.expandable_path? && !expansion.expand?(head)

        field_walk(target.path_children(version), rest, version, expansion.child(head), [*walked, head])
      end
      problems.include?(nil) ? nil : problems.first
    end

    # Deepest walk for reused copies (reference property:), whose objects differ on every call
    FIELD_PATH_DEPTH = 32
    private_constant :FIELD_PATH_DEPTH

    # A property already on the walked stack (a recursive association) is listed, but not walked again
    def collect_field_paths(properties, prefix, version, stack, paths)
      properties.each do |property|
        path = [*prefix, property.key]
        paths << path.join(".")
        target = property.path_target(version)
        next if stack.any? { |walked| walked.equal?(target) } || stack.size >= FIELD_PATH_DEPTH

        collect_field_paths(target.path_children(version), path, version, [*stack, target], paths)
      end
    end
  end
end
