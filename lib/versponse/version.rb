# frozen_string_literal: true

module Versponse
  # One version of a response class: its properties, views and identifier. Frozen once the version block closes.
  #
  # @api private
  class Version
    # @return [String] version name
    attr_reader :name
    # @return [Hash{String => Versponse::Properties::Base}] properties of the default view
    attr_reader :properties
    # @return [Hash{Symbol => Versponse::View}] declared and inherited views
    attr_reader :views
    # @return [Hash{String => Versponse::Properties::Field}] identifier fields, the implicit :collapsed view
    attr_reader :identifiers
    # @return [#call, nil] identifier condition called with (object, context); when it returns false,
    #   an expandable association that isn't expanded renders in full
    attr_reader :collapse_if
    # @return [String, nil] schema description
    attr_accessor :description
    # @return [Hash{String => Object}] camelized schema keywords of the version
    attr_accessor :schema_options

    # @param name [String] version name
    # @param owner [String] response class name, for messages
    def initialize(name:, owner:)
      @name = name
      @owner = owner
      @properties = {}
      @views = {}
      @identifiers = {}
      @collapse_if = nil
      @schema_options = {}
      @declared_keys = []
    end

    # @param property [Versponse::Properties::Base] property to add or replace
    # @return [Versponse::Properties::Base] the property
    # @raise [Versponse::DefinitionError] when an identifier declares the key
    def add(property)
      raise DefinitionError, "#{label}: #{property.key} is declared by identifier" if identifiers.key?(property.key)

      @declared_keys << property.key
      properties[property.key] = property
    end

    # The first identifier declared in a version replaces the inherited ones (and their collapse_if); later ones add to it
    #
    # @param property [Versponse::Properties::Field] identifier field
    # @param property_in_full [Versponse::Properties::Field] the field in the full shape (conditional with collapse_if)
    # @param collapse_if [#call, nil] normalized condition, at most one per version
    # @return [Versponse::Properties::Field] the field
    # @raise [Versponse::DefinitionError] when another identifier of the version already declares collapse_if
    def add_identifier(property, property_in_full: property, collapse_if: nil)
      if @inherited_identifiers
        # The old identifiers' conditional copies (collapse_if) go back to plain fields
        identifiers.each { |key, field| properties[key] = field if properties.key?(key) }
        @identifiers = {}
        @collapse_if = nil
        @inherited_identifiers = false
      end
      if collapse_if
        raise DefinitionError, "#{label}: collapse_if is already declared by another identifier" if @collapse_if

        @collapse_if = collapse_if
      end
      @declared_keys << property.key
      properties[property.key] = property_in_full
      identifiers[property.key] = property
    end

    # @return [Boolean] true when the version declares or inherits an identifier
    def identifiers?
      !identifiers.empty?
    end

    # @param name [Symbol, String] property to remove
    # @return [Versponse::Properties::Base] the removed property
    # @raise [Versponse::DefinitionError] when the property does not exist or is an identifier
    def remove(name)
      check_not_identifier!(name.to_s)
      properties.delete(name.to_s) || raise(DefinitionError, "Property #{name} not found in #{label}")
    end

    # @param view [Versponse::View] view to add or replace
    # @return [Versponse::View] the view
    # @raise [Versponse::DefinitionError] for the implicit default and collapsed views, or a view the version already declares
    def add_view(view)
      raise DefinitionError, "The #{view.name} view is implicit and can not be declared (#{label})" if %i[default collapsed].include?(view.name)
      raise DefinitionError, "#{label} declares view #{view.name} twice" if views[view.name]&.declared?

      views[view.name] = view
    end

    # @param other [Version] version to copy from
    # @param exclude_properties [Array<Symbol, String>] properties left out of the copy
    # @return [void]
    # @raise [Versponse::DefinitionError] when an excluded property does not exist in other, or is an identifier
    def copy_from(other, exclude_properties: [])
      excluded = exclude_properties.map(&:to_s)
      excluded.each { |key| raise DefinitionError, identifier_message(key) if other.identifiers.key?(key) }
      unknown = excluded - other.properties.keys
      raise DefinitionError, "#{label} excludes properties unknown in #{other.label}: #{unknown.join(", ")}" if unknown.any?

      @properties = other.properties.except(*excluded)
      @views = other.views.transform_values(&:for_next_version)
      @identifiers = other.identifiers.dup
      @collapse_if = other.collapse_if
      @inherited_identifiers = true
    end

    # Checks the views and freezes the version
    #
    # @return [Version] self
    # @raise [Versponse::DefinitionError] when a view excludes an unknown property, includes an unknown view
    #   or is part of an include cycle
    def finalize!
      # A key declared in this version replaces inherited views' view-only definitions of it
      views.each_value { |view| view.drop_inherited(@declared_keys) unless view.declared? }
      known = properties.keys | views.each_value.flat_map { |view| view.properties.keys }
      views.each_value do |view|
        view.check_excludes!(known, label)
        view.check_includes!(self)
        view.freeze
      end
      properties.freeze
      views.freeze
      identifiers.freeze
      schema_options.freeze
      freeze
    end

    # @return [Array<Symbol>] :default, the declared views, and :collapsed when there is an identifier
    def view_names
      identifiers? ? [:default, *views.keys, :collapsed] : [:default, *views.keys]
    end

    # @param view_name [Symbol, String] view name
    # @return [Array<Versponse::Properties::Base>] properties of the view in output order
    # @raise [Versponse::ViewNotFoundError] for an unknown view
    # @raise [Versponse::DefinitionError] for :collapsed without an identifier
    def properties_for(view_name)
      FieldOrder.call(declared_properties_for(view_name.to_sym), identifiers: identifiers.keys)
    end

    # @param view_name [Symbol, String] declared view name
    # @return [Versponse::View] the view
    # @raise [Versponse::ViewNotFoundError] for an unknown view
    def fetch_view(view_name)
      views.fetch(view_name.to_sym) do
        raise ViewNotFoundError, "View #{view_name} not found in #{label}. Available views: #{view_names.join(", ")}"
      end
    end

    # @return [String] "<class name> <version name>"
    def label
      "#{@owner} #{name}"
    end

    private

    # Excluding it would leave the collapsed shape rendering it
    def check_not_identifier!(key)
      raise DefinitionError, identifier_message(key) if identifiers.key?(key)
    end

    def identifier_message(key)
      "#{label}: #{key} is an identifier; redeclare the identifiers instead of excluding it"
    end

    def declared_properties_for(view_name)
      return properties.values if view_name == :default
      return collapsed_properties if view_name == :collapsed

      fetch_view(view_name).resolve(self)
    end

    def collapsed_properties
      raise DefinitionError, "#{label} has no identifier, so it has no collapsed view" unless identifiers?

      identifiers.values
    end
  end
end
