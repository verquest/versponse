# frozen_string_literal: true

module Versponse
  # Public class methods of {Versponse::Base}
  module Base::ClassMethods
    # Context used when serialize gets none (avoids two allocations per call)
    EMPTY_CONTEXT = {}.freeze

    # @return [Versponse::Versions] declared versions
    # @api private
    def versions
      @versions ||= Versions.new
    end

    # @param version [String] requested version
    # @return [Versponse::Version] closest declared version at or before it
    # @raise [Versponse::VersionNotFoundError] when there is none
    def resolve(version)
      versions.resolve(version.to_s)
    end

    # Renders an object, or each item of an Array-like collection, to a Hash with String keys
    #
    # @param object [Object, Hash, #to_ary] source
    # @param version [String, nil] requested version, config.current_version when nil
    # @param view [Symbol] view name
    # @param context [Hash] passed to blocks and conditions
    # @param root [String, Symbol, nil] wraps the result under this key
    # @param meta [Hash, nil] added under "meta" (requires root:)
    # @return [Hash, Array<Hash>] rendered output
    # @param expand [Array<String, Symbol>, nil] dotted paths of expandable associations to expand, or "*"
    # @raise [ArgumentError] without a version or with meta: but no root:
    # @raise [Versponse::InvalidExpandError] for unknown expand paths (config.unknown_expand = :raise)
    # @raise [Versponse::VersionNotFoundError] when no declared version matches
    # @raise [Versponse::ViewNotFoundError] for an unknown view
    # @raise [Versponse::ExtractionError] when reading a value fails
    def serialize(object, version: nil, view: :default, context: EMPTY_CONTEXT, root: nil, meta: nil, expand: nil)
      raise ArgumentError, "meta: requires root:" if meta && root.nil?

      version = version_name(version)
      plan = plan(version:, view:)
      expansion = expansion_for(expand, version:, view:)
      context = context.frozen? ? context : context.dup.freeze
      data = object.respond_to?(:to_ary) ? object.to_ary.map { |item| plan.call(item, context, expansion) } : plan.call(object, context, expansion)
      OutputValidator.call(self, data, version:, view:) if Versponse.configuration.validate_output
      wrap(data, root:, meta:)
    end

    # @param object [Object] source
    # @param options [Hash] see {#serialize}
    # @return [String] JSON produced by config.json_generator
    def to_json(object, **options)
      Versponse.configuration.json_generator.call(serialize(object, **options))
    end

    # OpenAPI schema with $refs to other components, or a root/meta wrapper schema
    #
    # @param version [String, nil] requested version, config.current_version when nil
    # @param view [Symbol] view name
    # @param root [String, Symbol, nil] builds a wrapper schema with the response under this key
    # @param meta [Class, nil] class whose $ref describes "meta" (requires root:)
    # @param collection [Boolean] the root key holds an array
    # @return [Hash] frozen schema
    # @raise [ArgumentError] with meta: but no root:
    def to_schema(version: nil, view: :default, root: nil, meta: nil, collection: false)
      raise ArgumentError, "meta: requires root:" if meta && root.nil?

      version = version_name(version)
      return DeepFreeze.call(wrapper_schema(view:, root:, meta:, collection:)) if root

      schemas.fetch([:openapi, version, view.to_sym]) do
        DeepFreeze.call(object_schema(version:, view:, context: SchemaContext.new(version:, validation: false)))
      end
    end

    # Schema with every reference inlined, for validation
    #
    # @param version [String, nil] requested version, config.current_version when nil
    # @param view [Symbol] view name
    # @param property [Symbol, String, nil] returns only this property's schema
    # @return [Hash] frozen schema
    # @raise [Versponse::PropertyNotFoundError] for an unknown property
    def to_validation_schema(version: nil, view: :default, property: nil)
      version = version_name(version)
      return property_validation_schema(version, view, property.to_s) if property

      schemas.fetch([:validation, version, view.to_sym]) do
        context = SchemaContext.new(version:, validation: true)
        DeepFreeze.call(context.inline([self, view.to_sym], component_name(view:)) { object_schema(version:, view:, context:) })
      end
    end

    # @param version [String] requested version name
    # @param view [Symbol] view name
    # @param context [Versponse::SchemaContext] schema generation context
    # @return [Hash] object schema of the version and view
    # @api private
    def object_schema(version:, view:, context:)
      definition = resolve(version)
      return ObjectSchema.build(definition.properties_for(:collapsed), context) if view.to_sym == :collapsed

      ObjectSchema.build(definition.properties_for(view), context, description: definition.description, schema_options: definition.schema_options)
    end

    # Component name without the view suffix: the class name without its first namespace, squashed.
    # Override it to rename components (e.g. strip a "Response" suffix).
    #
    # @return [String] base component name
    def base_component_name
      name.to_s.split("::", 2).last.to_s.delete(":")
    end

    # @param view [Symbol] view name
    # @return [String] component name, with the PascalCase view name for non-default views
    def component_name(view: :default)
      (view.to_sym == :default) ? base_component_name : base_component_name + Naming.pascalize(view)
    end

    # @param view [Symbol] view name
    # @param property [Symbol, String, nil] points at one property
    # @return [String] "#/components/schemas/<name>" reference
    def to_ref(view: :default, property: nil)
      base = "#/components/schemas/#{component_name(view:)}"
      property ? "#{base}/properties/#{property}" : base
    end

    # Every expandable dotted path of a response, for scope checks and expand: validation
    #
    # @param version [String, nil] requested version, config.current_version when nil
    # @param view [Symbol] view name
    # @return [Array<String>] sorted, frozen paths such as ["deal.stage", "site"]
    def expandable_paths(version: nil, view: :default)
      version = version_name(version)
      expandable_path_cache.fetch([version, view.to_sym]) do
        References.nested_paths(self, view: view.to_sym, version:, prefix: [], stack: []).map { |path| path.join(".") }.uniq.sort.freeze
      end
    end

    # @param version [String] canonical (declared) version name, as serialize and nested references pass it;
    #   raw client strings would grow the cache
    # @param view [Symbol] view name
    # @return [Versponse::Plan] compiled, cached plan
    # @api private
    def plan(version:, view: :default)
      plans.fetch([version, view.to_sym]) do
        definition = resolve(version)
        steps = definition.properties_for(view).map { |property| property.step(version:) }
        Plan.new(label: "#{name}[#{definition.name}/#{view}]", steps:)
      end
    end

    # @param version [String] canonical (declared) version name
    # @param view [Symbol] view name
    # @return [JSONSchemer::Schema] compiled, cached validation schema
    # @api private
    def schemer(version:, view: :default)
      schemers.fetch([version, view.to_sym]) do
        require "json_schemer"
        JSONSchemer.schema(to_validation_schema(version:, view:), meta_schema: JSONSchemer::OpenAPI31::BASE_URI.to_s)
      end
    end

    # @param version [String] canonical (declared) version name
    # @param view [Symbol] view name
    # @return [#valid?, nil] fast checker compiled from the validation schema, nil when it uses keywords the compiler does not support
    # @api private
    def checker(version:, view: :default)
      checkers.fetch([version, view.to_sym]) do
        Validator::Compiler.call(to_validation_schema(version:, view:), schemer(version:, view:))
      end
    end

    # Clears compiled plans, schemas, schemers, checkers and resolved versions
    #
    # @return [void]
    # @api private
    def reset_caches!
      plans.clear
      schemas.clear
      schemers.clear
      checkers.clear
      expandable_path_cache.clear
      versions.clear_resolved
    end

    private

    def plans
      @plans ||= Cache.new
    end

    def schemas
      @schemas ||= Cache.new
    end

    def schemers
      @schemers ||= Cache.new
    end

    def checkers
      @checkers ||= Cache.new
    end

    def expandable_path_cache
      @expandable_path_cache ||= Cache.new
    end

    def property_validation_schema(version, view, key)
      schemas.fetch([:validation, version, view.to_sym, key]) do
        target = resolve(version).properties_for(view).find { |property| property.key == key } ||
          raise(PropertyNotFoundError, "Property #{key} not found in #{name} #{version}/#{view}")
        DeepFreeze.call(target.schema(SchemaContext.new(version:, validation: true)))
      end
    end

    # Maps the requested version to a declared version name (of any class) before it reaches a cache,
    # so arbitrary client-sent strings can't grow the caches. Assumes the resolver picks the closest
    # earlier version, like the default one.
    def version_name(version)
      requested = version&.to_s || current_version_name
      Versponse.configuration.version_resolver.call(requested, Registry.version_names) || requested
    end

    def current_version_name
      current = Versponse.configuration.current_version
      raise ArgumentError, "version: is required when config.current_version is not set" unless current

      current.call.to_s
    end

    def wrapper_schema(view:, root:, meta:, collection:)
      item = {"$ref" => to_ref(view:)}
      properties = {root.to_s => collection ? {"type" => "array", "items" => item} : item}
      properties["meta"] = {"$ref" => meta.to_ref} if meta
      {"type" => "object", "required" => properties.keys, "properties" => properties, "additionalProperties" => false}
    end

    def expansion_for(expand, version:, view:)
      paths = Array(expand).map(&:to_s)
      return Expansion.build(paths) if paths.empty? || paths.include?("*")

      unknown = paths.reject { |path| expandable_path?(path, version:, view:) }
      return Expansion.build(paths) if unknown.empty?
      raise InvalidExpandError.new(paths: unknown) if Versponse.configuration.unknown_expand == :raise

      Expansion.build(paths - unknown)
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

    def wrap(data, root:, meta:)
      return data if root.nil?

      wrapped = {root.to_s => data}
      wrapped["meta"] = meta if meta
      wrapped
    end
  end
end
