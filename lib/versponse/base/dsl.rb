# frozen_string_literal: true

module Versponse
  # Class-level DSL of {Versponse::Base}. All methods are private class methods.
  module Base::DSL
    private

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
      target.schema_options = target.schema_options.merge(Naming.camelize_keys(options))
    end

    # Limits the versions the class serves; resolving a version outside the range raises
    # VersionNotFoundError. Subclasses inherit the range; no arguments removes an inherited one.
    #
    # @param min [String, nil] first supported version (inclusive), defaults to the first declared version
    # @param max [String, nil] last supported version (inclusive), defaults to no upper bound
    # @return [void]
    # @raise [Versponse::DefinitionError] when min sorts after max, inside a version, or after the first version
    def supported_versions(min: nil, max: nil)
      raise DefinitionError, "supported_versions must come before the first version" unless versions.empty?
      raise DefinitionError, "supported_versions can only be set on the class" if @current_scope

      @supported_versions = (min.nil? && max.nil?) ? nil : SupportedVersions.new(min:, max:)
      Versponse.reset_caches!
    end

    # Declares a version
    #
    # @param name [String] version name, compared as a String
    # @param inherit [Boolean, String] true copies the previously declared version, a String copies that exact version
    # @param exclude_properties [Array<Symbol>] inherited properties to leave out
    # @return [void]
    # @raise [Versponse::DefinitionError] when nested in another version
    # @raise [Versponse::VersionNotFoundError] when inherit: names no declared version
    def version(name, inherit: true, exclude_properties: [], &block)
      raise DefinitionError, "version blocks can not be nested" if @current_scope

      definition = Version.new(name: name.to_s, owner: self.name || "AnonymousResponse")
      source = version_source(inherit)
      definition.copy_from(source, exclude_properties:) if source
      @current_scope = definition
      instance_exec(&block) if block
      finish_version(definition)
    ensure
      @current_scope = nil
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
    # @param type [Symbol] string, number, integer or boolean
    # @param options [Hash] map:, nullable:, if:, unless:, JSON Schema keywords
    # @yieldparam object [Object] serialized object
    # @yieldparam context [Hash] serialize context
    # @return [void]
    def field(name, type: nil, **options, &block)
      add_property(Properties::Field, name:, type: type || default_options[:type], block:, **options)
    end

    # Declares a field of the collapsed shape, rendered for expandable associations that aren't expanded
    #
    # @param name [Symbol] output key
    # @param type [Symbol, nil] field type (with_options type:, else :string)
    # @param options [Hash] map:, nullable: and JSON Schema keywords (no if:/unless:); with_options defaults apply
    # @return [void]
    def identifier(name, type: nil, **options, &block)
      raise DefinitionError, "identifier must be declared inside a version" unless @current_scope.is_a?(Version)
      raise DefinitionError, "identifier #{name} takes no if: or unless:" if options.key?(:if) || options.key?(:unless)

      defaults = default_options.except(:type, :if, :unless)
      type ||= default_options[:type] || :string
      @current_scope.add_identifier(Properties::Field.new(**defaults, name:, type:, block:, **options))
    end

    # Declares a value from a fixed list
    #
    # @param name [Symbol] output key
    # @param values [Array] allowed values
    # @param options [Hash] see {#field}
    # @return [void]
    def enum(name, values:, **options, &block)
      add_property(Properties::Enum, name:, values:, block:, **options)
    end

    # Declares a constant
    #
    # @param name [Symbol] output key
    # @param value [Object] constant value
    # @param options [Hash] if:, unless:, JSON Schema keywords
    # @return [void]
    def const(name, value:, **options)
      add_property(Properties::Const, name:, value:, ignore_defaults: %i[map nullable], **options)
    end

    # Declares an array of scalars
    #
    # @param name [Symbol] output key
    # @param type [Symbol] item type
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
    # @param view [Symbol] view of item
    # @param options [Hash] see {#field}
    # @return [void]
    def collection(name, item: nil, view: :default, **options, &block)
      return add_property(Properties::Collection, name:, item:, view:, block:, **options) if item
      raise DefinitionError, "collection #{name} needs item: or a block defining its properties" unless block

      nested(add_property(Properties::Collection, name:, **options), &block)
    end

    # Declares a nested response class, or a variant inside one_of
    #
    # @param name [Symbol, nil] output key, omitted inside one_of
    # @param from [Class] class implementing the reference protocol
    # @param view [Symbol] view of from
    # @param property [Symbol, nil] one property of a non-Versponse class's schema
    # @param match [Class, Proc, nil] one_of matcher, compared with ===
    # @param options [Hash] see {#field}
    # @return [void]
    def reference(name = nil, from:, view: :default, property: nil, match: nil, **options, &block)
      return one_of_variant(name, from:, view:, match:, extra: options.any? || block || property) if @current_scope.is_a?(Properties::OneOf)
      raise DefinitionError, "reference needs a name outside one_of" if name.nil?
      raise DefinitionError, "#{name}: match: is only used for one_of variants" if match

      ignore_defaults = (property && References.versponse?(from)) ? %i[nullable] : []
      add_property(Properties::Reference, name:, from:, view:, property:, block:, ignore_defaults:, **options)
    end

    # Declares a polymorphic value; the block declares variants with reference from:, match:.
    # Without a name, inside a collection block, it types each item of the collection.
    #
    # @param name [Symbol, nil] output key; nil for the item one_of of a collection
    # @param discriminator [String, Symbol, nil] OpenAPI discriminator property
    # @param options [Hash] see {#field}; an item one_of takes only nullable: and schema keywords
    # @return [void]
    def one_of(name = nil, discriminator: nil, **options, &block)
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
      nested(definition, &block) if block
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

    # Applies options to every property declared in the block
    #
    # @param options [Hash] shared options
    # @return [void]
    def with_options(**options)
      previous = @default_options
      @default_options = default_options.merge(options)
      yield
    ensure
      @default_options = previous
    end

    def default_options
      @default_options || {}
    end

    def class_or_version(keyword)
      target = @current_scope || versions
      raise DefinitionError, "#{keyword} on the class must come before the first version" if target.is_a?(Versions) && !versions.empty?
      return target if target.is_a?(Versions) || target.is_a?(Version)

      raise DefinitionError, "#{keyword} can only be set on the class or a version"
    end

    def version_source(inherit)
      return versions.fetch(inherit) if inherit.is_a?(String)

      @last_version if inherit
    end

    def finish_version(definition)
      definition.description ||= versions.description
      definition.schema_options = versions.schema_options.merge(definition.schema_options)
      versions.add(definition.finalize!)
      @last_version = definition
      # Any class may embed this one in a plan or validation schema, so a reopened class (forward
      # declarations, verquest references) clears every cache; this only happens at definition time
      Versponse.reset_caches!
    end

    def one_of_variant(name, from:, view:, match:, extra:)
      raise DefinitionError, "one_of variants take no name, options or block (use source inside one_of)" if name || extra

      @current_scope.add_variant(from:, match:, view:)
    end

    def item_one_of(discriminator:, **options, &block)
      collection = @current_scope
      raise DefinitionError, "one_of without a name is only allowed inside a collection block" unless collection.is_a?(Properties::Collection)
      raise DefinitionError, "#{collection.key}: the item one_of takes no map:, if: or unless:" if options.key?(:map) || options.key?(:if) || options.key?(:unless)

      property = Properties::ItemOneOf.new(name: collection.key, discriminator:, **options)
      collection.items_one_of = property
      nested(property, &block)
      raise DefinitionError, "#{collection.key}: one_of needs at least one variant" unless property.variants?
    end

    def add_property(klass, ignore_defaults: [], **options)
      scope = @current_scope || raise(DefinitionError, "Properties must be declared inside a version block")
      property = klass.new(**default_options.except(:type, *ignore_defaults), **options)
      scope.add(property)
      property
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
