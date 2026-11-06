# frozen_string_literal: true

module Versponse
  # Public class methods of {Versponse::Base}
  module Base::ClassMethods
    # Context used when serialize gets none (avoids two allocations per call)
    EMPTY_CONTEXT = {}.freeze

    # Versions, resolution and caches of the class
    #
    # @return [Versponse::Internals] per-class internals
    # @api private
    def versponse
      @versponse ||= Internals.new(self)
    end

    # Renders an object, or each item of an Array-like collection, to a Hash with String keys
    #
    # @param object [Object, Hash, #to_ary, Set] source
    # @param version [String, nil] requested version, config.current_version when nil
    # @param view [Symbol] view name
    # @param context [Hash] passed to blocks and conditions
    # @param root [String, Symbol, nil] wraps the result under this key
    # @param meta [Hash, nil] added under "meta" with String keys (requires root:)
    # @return [Hash, Array<Hash>] rendered output
    # @param expand [Array<String, Symbol>, nil] dotted paths of expandable associations to expand, or "*"
    # @raise [ArgumentError] without a version or with meta: but no root:
    # @raise [Versponse::InvalidExpandError] for unknown expand paths (config.unknown_expand = :raise)
    # @raise [Versponse::VersionNotFoundError] when no declared version matches, or supported_versions leaves it out
    # @raise [Versponse::ViewNotFoundError] for an unknown view
    # @raise [Versponse::ExtractionError] when reading a value fails
    def serialize(object, version: nil, view: :default, context: EMPTY_CONTEXT, root: nil, meta: nil, expand: nil)
      raise ArgumentError, "meta: requires root:" if meta && root.nil?

      internals = versponse
      version = internals.version_name(version)
      plan = internals.plan(version:, view:)
      expansion = internals.expansion(expand, version:, view:)
      context = context.frozen? ? context : context.dup.freeze
      data = Collections.collection?(object) ? Collections.map(Collections.items(object)) { |item| plan.call(item, context, expansion) } : plan.call(object, context, expansion)
      OutputValidator.call(self, data, version:, view:) if Versponse.configuration.validate_output
      Wrapper.wrap(data, root:, meta:)
    end

    # @param object [Object] source
    # @param options [Hash] see {#serialize}
    # @return [String] JSON produced by config.json_generator
    def serialize_json(object, **options)
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

      version = versponse.version_name(version)
      return DeepFreeze.call(Wrapper.schema(self, view:, root:, meta:, collection:)) if root

      versponse.openapi_schema(version:, view:)
    end

    # Schema with every reference inlined, for validation
    #
    # @param version [String, nil] requested version, config.current_version when nil
    # @param view [Symbol] view name
    # @param property [Symbol, String, nil] returns only this property's schema
    # @return [Hash] frozen schema
    # @raise [Versponse::PropertyNotFoundError] for an unknown property
    def to_validation_schema(version: nil, view: :default, property: nil)
      version = versponse.version_name(version)
      return versponse.property_validation_schema(version:, view:, key: property.to_s) if property

      versponse.validation_schema(version:, view:)
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
      versponse.expandable_paths(version: versponse.version_name(version), view:)
    end
  end
end
