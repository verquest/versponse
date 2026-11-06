# frozen_string_literal: true

module Versponse
  # Class-level DSL of {Versponse::Base}. All methods are private class methods; they delegate to the
  # class's {Versponse::Builder}, which holds the definition state.
  module Base::DSL
    private

    # Sets the description of the class or the current version
    #
    # @param text [String] description
    # @return [void]
    def description(text)
      versponse.builder.description(text)
    end

    # Adds schema keywords to the class or the current version
    #
    # @param options [Hash] JSON Schema keywords in snake_case
    # @return [void]
    def schema_options(**options)
      versponse.builder.schema_options(**options)
    end

    # Limits the versions the class serves; resolving a version outside the range raises
    # VersionNotFoundError. Subclasses inherit the range; no arguments removes an inherited one.
    #
    # @param min [String, nil] first supported version (inclusive), defaults to the first declared version
    # @param max [String, nil] last supported version (inclusive), defaults to no upper bound
    # @return [void]
    # @raise [Versponse::DefinitionError] when min sorts after max, inside a version, or after the first version
    def supported_versions(min: nil, max: nil)
      versponse.builder.supported_versions(min:, max:)
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
      versponse.builder.version(name, inherit:, exclude_properties:, &block)
    end

    # Computes the value of the enclosing inline object, inline collection or one_of
    #
    # @yieldparam object [Object] serialized object
    # @yieldparam context [Hash] serialize context
    # @return [void]
    def source(&block)
      versponse.builder.source(&block)
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
      versponse.builder.field(name, type:, **options, &block)
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
      versponse.builder.identifier(name, type:, collapse_if:, **options, &block)
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
      versponse.builder.enum(name, values:, type:, **options, &block)
    end

    # Declares a constant
    #
    # @param name [Symbol] output key
    # @param value [Object] constant value
    # @param options [Hash] if:, unless:, JSON Schema keywords
    # @return [void]
    def const(name, value:, **options)
      versponse.builder.const(name, value:, **options)
    end

    # Declares an array of scalars
    #
    # @param name [Symbol] output key
    # @param type [Symbol, Array<Symbol>] item type, or a union like [:integer, :string]
    # @param item_schema_options [Hash] JSON Schema keywords of each item
    # @param options [Hash] see {#field}
    # @return [void]
    def array(name, type: nil, item_schema_options: {}, **options, &block)
      versponse.builder.array(name, type:, item_schema_options:, **options, &block)
    end

    # Declares an inline object; the block defines its properties
    #
    # @param name [Symbol] output key
    # @param options [Hash] map: (use "." for the same object), nullable:, if:, unless:, JSON Schema keywords
    # @return [void]
    def object(name, **options, &block)
      versponse.builder.object(name, **options, &block)
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
      versponse.builder.collection(name, item:, view:, **options, &block)
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
      versponse.builder.reference(name, from:, view:, property:, match:, **options, &block)
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
      versponse.builder.one_of(positional_name, name:, discriminator:, **options, &block)
    end

    # Declares a view inside a version
    #
    # @param name [Symbol] view name
    # @return [void]
    def view(name, &block)
      versponse.builder.view(name, &block)
    end

    # Applies another view's operations inside a view
    #
    # @param name [Symbol] included view
    # @return [void]
    def include_view(name)
      versponse.builder.include_view(name)
    end

    # Removes properties from the current version or view
    #
    # @param names [Array<Symbol>] property names
    # @return [void]
    def exclude_properties(*names)
      versponse.builder.exclude_properties(*names)
    end

    # Applies options to every property declared in the block
    #
    # @param options [Hash] shared options
    # @return [void]
    def with_options(**options, &block)
      versponse.builder.with_options(**options, &block)
    end
  end
end
