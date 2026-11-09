# frozen_string_literal: true

module Versponse
  # Builds the versions of one response class from its DSL calls ({Versponse::Base::DSL} delegates here).
  # Holds the definition state (current scope, with_options defaults, last version), so none of it lives
  # on the response class itself.
  #
  # @api private
  class Builder
    # @param klass [Class] response class
    def initialize(klass)
      @klass = klass
      @current_scope = nil
      @default_options = nil
      @last_version = nil
    end

    # Sets the description of the class or the current version
    #
    # @param text [String] description
    # @return [void]
    def description(text)
      class_or_version(:description).description = text
    end

    # Adds schema keywords to the class or the current version
    #
    # @param options [Hash] JSON Schema keywords in snake_case
    # @return [void]
    def schema_options(**options)
      target = class_or_version(:schema_options)
      keywords = Naming.camelize_keys(options)
      check_schema_options!(keywords)
      target.schema_options = target.schema_options.merge(keywords)
    end

    # Limits the versions the class serves; resolving a version outside the range raises
    # VersionNotFoundError. Subclasses inherit the range; no arguments removes an inherited one.
    #
    # @param min [String, nil] first supported version (inclusive), defaults to the first declared version
    # @param max [String, nil] last supported version (inclusive), defaults to no upper bound
    # @return [void]
    # @raise [Versponse::DefinitionError] when min sorts after max, inside a version, or after the first version
    def supported_versions(min: nil, max: nil)
      raise DefinitionError, "supported_versions must come before the first version" unless @klass.versponse.versions.empty?
      raise DefinitionError, "supported_versions can only be set on the class" if @current_scope

      range = (min.nil? && max.nil?) ? nil : SupportedVersions.new(min:, max:)
      @klass.versponse.supported_version_range = range
      Registry.add_range(range) if range
      Versponse.reset_caches!
    end

    # Sets the fraction digits of date-time values, from a version on when from: is given
    #
    # @param digits [Integer] fraction digits from 0 (whole seconds) to 9
    # @param from [String, nil] first version it applies to
    # @return [void]
    # @raise [Versponse::DefinitionError] inside a version, after the first version, for invalid digits,
    #   or when the class already sets the precision from that version
    def time_precision(digits, from: nil)
      raise DefinitionError, "time_precision can only be set on the class" if @current_scope
      raise DefinitionError, "time_precision must come before the first version" unless @klass.versponse.versions.empty?
      raise DefinitionError, "time_precision must be an Integer from 0 to 9, got #{digits.inspect}" unless digits.is_a?(Integer) && digits.between?(0, 9)

      from = from&.to_s
      @klass.versponse.add_time_precision(digits, from:)
      Registry.add_version_name(from) if from
      Versponse.reset_caches!
    end

    # Replaces nil values of the class's field, enum and array properties without default:
    #
    # @param callable [#call, nil] called with (object, key, context); nil removes an inherited one
    # @return [void]
    # @raise [Versponse::DefinitionError] inside a version, after the first version, or for a value that can't take
    #   (object, key, context)
    def on_nil(callable)
      class_setting!(:on_nil)
      raise DefinitionError, "on_nil must be a callable taking (object, key, context), or nil to remove an inherited one" unless callable.nil? || Callable.accepts?(callable, 3)

      @klass.versponse.on_nil = callable
      Versponse.reset_caches!
    end

    # Policy for the class's failing properties without their own on_error:
    #
    # @param policy [Symbol, #call, nil] :raise, :nullify, :omit, a handler, or nil to remove an inherited one
    # @return [void]
    # @raise [Versponse::DefinitionError] inside a version, after the first version, or for an unknown policy
    def on_error(policy)
      class_setting!(:on_error)
      raise DefinitionError, "on_error must be :raise, :nullify, :omit or a callable taking (error, object, key, context)" unless policy.nil? || ErrorPolicy.valid?(policy)

      @klass.versponse.on_error = policy
      Versponse.reset_caches!
    end

    # Declares the keys serialize_json and OpenAPI wrappers wrap the class's output under
    #
    # @param name [String, Symbol] root of one object
    # @param collection [String, Symbol, nil] root of a collection; name pluralized with String#pluralize when nil
    # @return [void]
    # @raise [Versponse::DefinitionError] inside a version, or without collection: when String#pluralize is undefined
    def root(name, collection: nil)
      raise DefinitionError, "root can only be set on the class" if @current_scope

      name = name.to_s
      @klass.versponse.roots = [name, collection&.to_s || pluralize_root(name)].freeze
    end

    # Declares a version
    #
    # @param name [String] version name, compared as a String
    # @param inherit [Boolean, String, Symbol] true copies the previously declared version, a name copies the
    #   closest version at or before it
    # @param exclude_properties [Array<Symbol>] inherited properties to leave out
    # @return [void]
    # @raise [Versponse::DefinitionError] when nested in another version
    # @raise [Versponse::DefinitionError] when inherit: names a version before every declared one
    def version(name, inherit: true, exclude_properties: [], &block)
      raise DefinitionError, "version blocks can not be nested" if @current_scope

      # As in verquest, a version block starts without with_options defaults
      outer_defaults = @default_options
      @default_options = nil
      begin
        definition = Version.new(name: name.to_s, owner: @klass.name || "AnonymousResponse")
        source = version_source(inherit)
        raise DefinitionError, "#{definition.label}: exclude_properties: needs a version to inherit from" if source.nil? && exclude_properties.any?

        definition.copy_from(source, exclude_properties:) if source
        @current_scope = definition
        @klass.instance_exec(&block) if block
        finish_version(definition)
      ensure
        @current_scope = nil
        @default_options = outer_defaults
      end
    end

    # Computes the value of the enclosing inline object, inline collection or one_of
    #
    # @yieldparam object [Object] serialized object
    # @yieldparam context [Hash] serialize context
    # @return [void]
    def source(&block)
      raise DefinitionError, "source can only be used inside object, collection or one_of" unless @current_scope.is_a?(Properties::Base)

      @current_scope.source = block
    end

    # Declares a scalar field
    #
    # @param name [Symbol] output key
    # @param type [Symbol, Array<Symbol>] string, number, integer, boolean, object, a custom type, or a union like [:integer, :string]
    # @param options [Hash] map:, nullable:, if:, unless:, JSON Schema keywords
    # @yieldparam object [Object] serialized object
    # @yieldparam context [Hash] serialize context
    # @return [void]
    def field(name, type: nil, **options, &block)
      add_property(Properties::Field, name:, type: type || default_options[:type], block:, **options)
    end

    # Declares a field of both the full shape and the collapsed shape, rendered for expandable associations that aren't expanded
    #
    # @param name [Symbol] output key
    # @param type [Symbol, nil] field type (with_options type:, else :string)
    # @param collapse_if [Proc, #call, nil] (not taken from with_options) called with (object) or (object, context); when it returns false the
    #   association renders in full instead (a collection item: when it is false for any item), and the full shape leaves this field out.
    #   One per version.
    # @param options [Hash] map:, nullable:, description: and JSON Schema keywords (no if:/unless:); with_options defaults apply
    # @return [void]
    # @raise [Versponse::DefinitionError] outside a version, with if:/unless:, or with a collapse_if: that doesn't respond to call
    def identifier(name, type: nil, collapse_if: nil, **options, &block)
      raise DefinitionError, "identifier must be declared inside a version" unless @current_scope.is_a?(Version)
      raise DefinitionError, "identifier #{name} takes no if: or unless:" if options.key?(:if) || options.key?(:unless)
      raise DefinitionError, "identifier #{name}: collapse_if: must respond to call" unless collapse_if.nil? || collapse_if.respond_to?(:call)

      defaults = default_options.except(:type, :if, :unless, :collapse_if, :view, :discriminator, :context)
      type ||= default_options[:type] || :string
      identifier = Properties::Field.new(**defaults, name:, type:, block:, **options)
      property = collapse_if ? Properties::Field.new(**defaults, name:, type:, block:, if: collapse_if, **options) : identifier
      @current_scope.add_identifier(identifier, property_in_full: property, collapse_if: Callable.normalize(collapse_if))
    end

    # Declares a value from a fixed list
    #
    # @param name [Symbol] output key
    # @param type [Symbol, Array<Symbol>, nil] type of the values, as for {#field} (with_options type:); inferred from the values when nil
    # @param values [Array] allowed values, each of the type
    # @param options [Hash] see {#field}
    # @return [void]
    # @raise [Versponse::DefinitionError] when the type can't be inferred, or a value isn't of the type
    def enum(name, values:, type: nil, **options, &block)
      add_property(Properties::Enum, name:, values:, type: type || default_options[:type], block:, **options)
    end

    # Declares a constant
    #
    # @param name [Symbol] output key
    # @param value [Object] constant value
    # @param options [Hash] if:, unless:, JSON Schema keywords
    # @return [void]
    def const(name, value:, **options, &block)
      add_property(Properties::Const, name:, value:, block:, ignore_defaults: %i[map nullable], **options)
    end

    # Declares an array of scalars
    #
    # @param name [Symbol] output key
    # @param type [Symbol, Array<Symbol>] item type, or a union like [:integer, :string]
    # @param item_schema_options [Hash] JSON Schema keywords of each item
    # @param options [Hash] see {#field}
    # @return [void]
    def array(name, type: nil, item_schema_options: {}, **options, &block)
      add_property(Properties::Array, name:, type: type || default_options[:type], item_schema_options:, block:, **options)
    end

    # Declares an inline object; the block defines its properties
    #
    # @param name [Symbol] output key
    # @param options [Hash] map: (use "." for the same object), nullable:, if:, unless:, JSON Schema keywords
    # @return [void]
    def object(name, **options, &block)
      raise DefinitionError, "object #{name} needs a block defining its properties" unless block

      nested(add_property(Properties::Object, name:, **options), &block)
    end

    # Declares an array of objects, either of another response class (item:) or inline (block)
    #
    # With item:, a block computes the value. Without item:, the block defines the item properties.
    #
    # @param name [Symbol] output key
    # @param item [Class, nil] class implementing the reference protocol
    # @param view [Symbol, nil] view of item (with_options view:, else :default)
    # @param options [Hash] see {#field}
    # @return [void]
    def collection(name, item: nil, view: nil, **options, &block)
      view ||= default_options[:view] || :default
      return add_property(Properties::Collection, name:, item:, view:, block:, **options) if item
      raise DefinitionError, "collection #{name} needs item: or a block defining its properties" unless block

      nested(add_property(Properties::Collection, name:, **options), &block)
    end

    # Declares a nested response class, or a variant inside one_of
    #
    # @param name [Symbol, nil] output key, omitted inside one_of
    # @param from [Class] class implementing the reference protocol
    # @param view [Symbol, nil] view of from (with_options view:, else :default)
    # @param property [Symbol, nil] one property of a non-Versponse class's schema
    # @param match [Class, Proc, nil] one_of matcher, compared with ===
    # @param options [Hash] see {#field}
    # @return [void]
    def reference(name = nil, from:, view: nil, property: nil, match: nil, **options, &block)
      view ||= default_options[:view] || :default
      if @current_scope.is_a?(Properties::OneOf)
        return one_of_variant(name, from:, view:, match:, context: options[:context], extra: options.except(:context).any? || block || property)
      end
      raise DefinitionError, "reference needs a name outside one_of" if name.nil?
      raise DefinitionError, "#{name}: match: is only used for one_of variants" if match

      ignore_defaults = (property && References.versponse?(from)) ? %i[nullable context] : []
      add_property(Properties::Reference, name:, from:, view:, property:, block:, ignore_defaults:, **options)
    end

    # Declares a polymorphic value; the block declares variants with reference from:, match:.
    # Without a name, inside a collection block, it types each item of the collection.
    #
    # @param positional_name [Symbol, nil] output key; nil for the item one_of of a collection
    # @param name [Symbol, nil] the output key as a keyword, as verquest writes it
    # @param discriminator [String, Symbol, nil] OpenAPI discriminator property
    # @param options [Hash] see {#field}; an item one_of takes only nullable: and schema keywords
    # @return [void]
    # @raise [Versponse::DefinitionError] when the name is given both ways
    def one_of(positional_name = nil, name: nil, discriminator: nil, **options, &block)
      raise DefinitionError, "one_of #{positional_name}: give the name once, not also as name:" if positional_name && name

      name ||= positional_name
      discriminator ||= default_options[:discriminator]
      raise DefinitionError, "#{"one_of #{name}".strip} needs a block declaring its variants" unless block
      return item_one_of(discriminator:, **options, &block) if name.nil?

      property = add_property(Properties::OneOf, name:, discriminator:, **options)
      nested(property, &block)
      raise DefinitionError, "one_of #{name} needs at least one variant" unless property.variants?
    end

    # Declares a view inside a version
    #
    # @param name [Symbol] view name
    # @return [void]
    def view(name, &block)
      raise DefinitionError, "view must be declared inside a version" unless @current_scope.is_a?(Version)

      definition = View.new(name:)
      @current_scope.add_view(definition)
      @view_version = @current_scope
      nested(definition, &block) if block
    ensure
      @view_version = nil
    end

    # Applies another view's operations inside a view
    #
    # @param name [Symbol] included view
    # @return [void]
    def include_view(name)
      raise DefinitionError, "include_view can only be used inside a view" unless @current_scope.is_a?(View)

      @current_scope.include_view(name)
    end

    # Removes properties from the current version or view
    #
    # @param names [Array<Symbol>] property names
    # @return [void]
    def exclude_properties(*names)
      case @current_scope
      when Version then names.each { |name| @current_scope.remove(name) }
      when View then @current_scope.exclude(names)
      else raise DefinitionError, "exclude_properties can only be used inside a version or a view"
      end
    end

    # Applies options to every property declared in the block. A nested with_options replaces the outer
    # options, and map: is ignored, as in verquest.
    #
    # @param options [Hash] shared options
    # @return [void]
    def with_options(**options)
      previous = @default_options
      # As in verquest: a nested block replaces the outer options, and map: never applies to a group
      @default_options = options.except(:map)
      yield
    ensure
      @default_options = previous
    end

    private

    def class_setting!(name)
      raise DefinitionError, "#{name} can only be set on the class" if @current_scope
      raise DefinitionError, "#{name} must come before the first version" unless @klass.versponse.versions.empty?
    end

    def pluralize_root(name)
      return name.pluralize if name.respond_to?(:pluralize)

      raise DefinitionError, "root #{name.inspect} needs collection: when String#pluralize is undefined (ActiveSupport isn't loaded)"
    end

    def default_options
      @default_options || {}
    end

    def class_or_version(keyword)
      target = @current_scope || @klass.versponse.versions
      raise DefinitionError, "#{keyword} on the class must come before the first version" if target.is_a?(Versions) && !@klass.versponse.versions.empty?
      return target if target.is_a?(Versions) || target.is_a?(Version)

      raise DefinitionError, "#{keyword} can only be set on the class or a version"
    end

    def version_source(inherit)
      return inherited_version(inherit.to_s) if inherit.is_a?(String) || inherit.is_a?(Symbol)

      @last_version if inherit
    end

    # Resolves like a request (and like verquest's inherit:), ignoring supported_versions
    def inherited_version(name)
      versions = @klass.versponse.versions
      resolved = Versponse.configuration.version_resolver.call(name, versions.sorted_names)
      return versions.fetch(resolved) if resolved

      raise DefinitionError, "inherit: no version of #{@klass.name || "AnonymousResponse"} at or before #{name} (declared: #{versions.sorted_names.join(", ")})"
    end

    def finish_version(definition)
      @klass.versponse.versions.add(definition.finalize!)
      @last_version = definition
      # Any class may embed this one in a plan or validation schema, so a reopened class (forward
      # declarations, verquest references) clears every cache; this only happens at definition time
      Versponse.reset_caches!
    end

    def one_of_variant(name, from:, view:, match:, context:, extra:)
      raise DefinitionError, "one_of variants take no name, block or options besides view:, match: and context: (use source inside one_of)" if name || extra

      @current_scope.add_variant(from:, match:, view:, context:)
    end

    def item_one_of(discriminator:, **options, &block)
      collection = @current_scope
      raise DefinitionError, "one_of without a name is only allowed inside a collection block" unless collection.is_a?(Properties::Collection)
      if options.key?(:map) || options.key?(:if) || options.key?(:unless) || options.key?(:context)
        raise DefinitionError, "#{collection.key}: the item one_of takes no map:, if:, unless: or context: (give context: to the collection)"
      end

      property = Properties::ItemOneOf.new(name: collection.key, discriminator:, **default_options.slice(:nullable), **options)
      collection.items_one_of = property
      nested(property, &block)
      raise DefinitionError, "#{collection.key}: one_of needs at least one variant" unless property.variants?
    end

    def add_property(klass, ignore_defaults: [], **options)
      scope = @current_scope || raise(DefinitionError, "Properties must be declared inside a version block")
      defaults = default_options.except(:type, :collapse_if, :view, :discriminator, *ignore_defaults)
      target = options[:from] || options[:item]
      takes_context = klass.context_option? && (target.nil? || References.versponse?(target))
      defaults = defaults.except(:context) unless takes_context
      defaults = defaults.except(:default) unless klass.default_option?
      property = klass.new(**defaults, **options)
      if scope.is_a?(View) && @view_version&.identifiers&.key?(property.key)
        raise DefinitionError, "#{@view_version.label}: #{property.key} is declared by identifier"
      end

      scope.add(property)
      property
    end

    # Class- and version-level keywords: the property keywords and x- extensions, but not the object
    # keywords the object schema writes itself
    def check_schema_options!(keywords)
      unknown = keywords.keys.reject do |keyword|
        keyword.start_with?("x-") || (Properties::Base::SCHEMA_KEYWORDS.include?(keyword) && !%w[properties required].include?(keyword))
      end
      raise DefinitionError, "schema_options: unknown or reserved keywords #{unknown.join(", ")}" if unknown.any?
    end

    def nested(scope)
      previous = @current_scope
      @current_scope = scope
      yield
    ensure
      @current_scope = previous
    end
  end
end
