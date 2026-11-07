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
    # @param fields [Array<String, Symbol>, nil] dotted paths of the fields to render (identifiers and consts always
    #   render), "*" or nil for all
    # @raise [ArgumentError] without a version or with meta: but no root:
    # @raise [Versponse::InvalidExpandError] for unknown expand paths (config.unknown_expand = :raise)
    # @raise [Versponse::InvalidFieldsError] for unknown paths or paths below unexpanded associations
    #   (config.unknown_fields = :raise)
    # @raise [Versponse::VersionNotFoundError] when no declared version matches, or supported_versions leaves it out
    # @raise [Versponse::ViewNotFoundError] for an unknown view
    # @raise [Versponse::ExtractionError] when reading a value fails
    def serialize(object, version: nil, view: :default, context: EMPTY_CONTEXT, root: nil, meta: nil, expand: nil, fields: nil)
      raise ArgumentError, "meta: requires root:" if meta && root.nil?

      internals = versponse
      internals.requesting(version) do |canonical|
        plan = internals.plan(version: canonical, view:)
        expansion = internals.expansion(expand, version: canonical, view:)
        selection = internals.selection(fields, version: canonical, view:, expansion:) unless fields.nil?
        context = context.frozen? ? context : context.dup.freeze
        validate = Versponse.configuration.validate_output && OutputValidator.enabled?(self)
        if selection && !selection.all?
          # Validating plans prove the full shape, so a selection renders with the plain plan
          data = render(object, plan, context, Selection::Scope.new(expansion, selection))
          OutputValidator.call(self, data, version: canonical, view:, selection:) if validate
        # A validating plan checks while rendering; the output goes through OutputValidator only when a check failed
        elsif validate && (inline = internals.validating_plan(version: canonical, view:))
          data = nil
          failed = InlineValidation.run { data = render(object, inline, context, expansion) }
          OutputValidator.call(self, data, version: canonical, view:) if failed
        else
          data = Collections.collection?(object) ? Collections.map(Collections.items(object)) { |item| plan.call(item, context, expansion) } : plan.call(object, context, expansion)
          OutputValidator.call(self, data, version: canonical, view:) if validate
        end
        Wrapper.wrap(data, root:, meta:)
      end
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
    # @raise [Versponse::VersionNotFoundError] when the class doesn't serve the version (wrappers too)
    # @raise [Versponse::ViewNotFoundError] for an unknown view (wrappers too)
    def to_schema(version: nil, view: :default, root: nil, meta: nil, collection: false)
      raise ArgumentError, "meta: requires root:" if meta && root.nil?

      versponse.requesting(version) do |canonical|
        next versponse.openapi_schema(version: canonical, view:) unless root

        # The wrapper only refers to the component, but the version and view must exist like for any schema
        versponse.resolve(canonical).properties_for(view)
        DeepFreeze.call(Wrapper.schema(self, view:, root:, meta:, collection:))
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
      versponse.requesting(version) do |canonical|
        next versponse.property_validation_schema(version: canonical, view:, key: property.to_s) if property

        versponse.validation_schema(version: canonical, view:)
      end
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
    # @raise [Versponse::DefinitionError] for an anonymous class, which has no component name
    def to_ref(view: :default, property: nil)
      raise DefinitionError, "anonymous response classes have no component; name the class or override base_component_name" if base_component_name.empty?

      base = "#/components/schemas/#{component_name(view:)}"
      property ? "#{base}/properties/#{property}" : base
    end

    # Every expandable dotted path of a response, for scope checks and expand: validation
    #
    # @param version [String, nil] requested version, config.current_version when nil
    # @param view [Symbol] view name
    # @return [Array<String>] sorted, frozen paths such as ["deal.stage", "site"]
    def expandable_paths(version: nil, view: :default)
      versponse.requesting(version) { |canonical| versponse.expandable_paths(version: canonical, view:) }
    end

    # Every dotted path serialize fields: accepts, for docs and scope checks
    #
    # @param version [String, nil] requested version, config.current_version when nil
    # @param view [Symbol] view name
    # @return [Array<String>] sorted, frozen paths such as ["id", "site", "site.name"]
    def selectable_paths(version: nil, view: :default)
      versponse.requesting(version) { |canonical| versponse.selectable_paths(version: canonical, view:) }
    end

    private

    # @param object [Object] source, or a collection of them
    # @param plan [#call] plan of one object
    # @param context [Hash] frozen serialize context
    # @param expansion [Versponse::Expansion, Versponse::Selection::Scope] expand tree, paired with the selection in a
    #   selected render
    # @return [Hash, Array<Hash>] rendered output
    def render(object, plan, context, expansion)
      Collections.collection?(object) ? Collections.map(Collections.items(object)) { |item| plan.call(item, context, expansion) } : plan.call(object, context, expansion)
    end
  end
end
