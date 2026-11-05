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
      @schema_options = {}
    end

    # @param property [Versponse::Properties::Base] property to add or replace
    # @return [Versponse::Properties::Base] the property
    def add(property)
      properties[property.key] = property
    end

    # The first identifier declared in a version replaces the inherited ones; later ones add to it
    #
    # @param property [Versponse::Properties::Field] identifier field
    # @return [Versponse::Properties::Field] the field
    def add_identifier(property)
      if @inherited_identifiers
        @identifiers = {}
        @inherited_identifiers = false
      end
      identifiers[property.key] = property
    end

    # @return [Boolean] true when the version declares or inherits an identifier
    def identifiers?
      !identifiers.empty?
    end

    # @param name [Symbol, String] property to remove
    # @return [Versponse::Properties::Base] the removed property
    # @raise [Versponse::PropertyNotFoundError] when the property does not exist
    def remove(name)
      properties.delete(name.to_s) || raise(PropertyNotFoundError, "Property #{name} not found in #{label}")
    end

    # @param view [Versponse::View] view to add or replace
    # @return [Versponse::View] the view
    # @raise [Versponse::DefinitionError] for the implicit default and collapsed views
    def add_view(view)
      raise DefinitionError, "The #{view.name} view is implicit and can not be declared (#{label})" if %i[default collapsed].include?(view.name)

      views[view.name] = view
    end

    # @param other [Version] version to copy from
    # @param exclude_properties [Array<Symbol, String>] properties left out of the copy
    # @return [void]
    # @raise [Versponse::PropertyNotFoundError] when an excluded property does not exist in other
    def copy_from(other, exclude_properties: [])
      excluded = exclude_properties.map(&:to_s)
      unknown = excluded - other.properties.keys
      raise PropertyNotFoundError, "#{label} excludes properties unknown in #{other.label}: #{unknown.join(", ")}" if unknown.any?

      @properties = other.properties.except(*excluded)
      @views = other.views.transform_values(&:for_next_version)
      @identifiers = other.identifiers.dup
      @inherited_identifiers = true
    end

    # Checks the views and freezes the version
    #
    # @return [Version] self
    # @raise [Versponse::PropertyNotFoundError] when a view excludes an unknown property
    def finalize!
      known = properties.keys | views.each_value.flat_map { |view| view.properties.keys }
      views.each_value do |view|
        view.check_excludes!(known, label)
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
      view_name = view_name.to_sym
      return properties.values if view_name == :default
      return collapsed_properties if view_name == :collapsed

      fetch_view(view_name).resolve(self)
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

    def collapsed_properties
      raise DefinitionError, "#{label} has no identifier, so it has no collapsed view" unless identifiers?

      identifiers.values
    end
  end
end
