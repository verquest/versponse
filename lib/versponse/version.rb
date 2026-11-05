# frozen_string_literal: true

module Versponse
  # One version of a response class: its properties and views. Frozen once the version block closes.
  #
  # @api private
  class Version
    # @return [String] version name
    attr_reader :name
    # @return [Hash{String => Versponse::Properties::Base}] properties of the default view
    attr_reader :properties
    # @return [Hash{Symbol => Versponse::View}] declared and inherited views
    attr_reader :views
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
      @schema_options = {}
    end

    # @param property [Versponse::Properties::Base] property to add or replace
    # @return [Versponse::Properties::Base] the property
    def add(property)
      properties[property.key] = property
    end

    # @param name [Symbol, String] property to remove
    # @return [Versponse::Properties::Base] the removed property
    # @raise [Versponse::PropertyNotFoundError] when the property does not exist
    def remove(name)
      properties.delete(name.to_s) || raise(PropertyNotFoundError, "Property #{name} not found in #{label}")
    end

    # @param view [Versponse::View] view to add or replace
    # @return [Versponse::View] the view
    # @raise [Versponse::DefinitionError] for the reserved default view
    def add_view(view)
      raise DefinitionError, "The default view is implicit and can not be declared (#{label})" if view.name == :default

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
      schema_options.freeze
      freeze
    end

    # @return [Array<Symbol>] :default followed by the declared views
    def view_names
      [:default, *views.keys]
    end

    # @param view_name [Symbol, String] view name
    # @return [Array<Versponse::Properties::Base>] properties of the view in output order
    # @raise [Versponse::ViewNotFoundError] for an unknown view
    def properties_for(view_name)
      return properties.values if view_name.to_sym == :default

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
  end
end
