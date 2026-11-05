# frozen_string_literal: true

module Versponse
  # A named selection of a version's properties: include_view, exclude_properties and view-only properties
  #
  # @api private
  class View
    # @return [Symbol] view name
    attr_reader :name
    # @return [Hash{String => Versponse::Properties::Base}] properties declared only in this view
    attr_reader :properties

    # @param name [Symbol, String] view name
    # @param operations [Array<Array>] [type, argument] pairs in declaration order
    # @param properties [Hash] view-only properties
    # @param inherited [Boolean] true when copied from an earlier version
    def initialize(name:, operations: [], properties: {}, inherited: false)
      @name = name.to_sym
      @operations = operations
      @properties = properties
      @inherited = inherited
    end

    # @param property [Versponse::Properties::Base] view-only property
    # @return [void]
    def add(property)
      properties[property.key] = property
      @operations << [:add, property.key]
    end

    # @param name [Symbol, String] view whose operations are applied here
    # @return [void]
    # @raise [Versponse::DefinitionError] for :default, which every view already starts from
    def include_view(name)
      raise DefinitionError, "include_view :default is implicit, every view starts from default" if name.to_sym == :default

      @operations << [:include, name.to_sym]
    end

    # @param names [Array<Symbol, String>] properties to remove
    # @return [void]
    def exclude(names)
      @operations << [:exclude, names.map(&:to_s)]
    end

    # @return [View] a copy for a later version, whose unknown excludes are ignored
    def for_next_version
      View.new(name:, operations: @operations.dup, properties: @properties.dup, inherited: true)
    end

    # @param known [Array<String>] property keys known in the declaring version
    # @param label [String] version label for the error message
    # @return [nil]
    # @raise [Versponse::PropertyNotFoundError] when a declared (not inherited) view excludes an unknown property
    def check_excludes!(known, label)
      return if @inherited

      @operations.each do |type, argument|
        next unless type == :exclude

        unknown = argument - known
        raise PropertyNotFoundError, "View #{name} in #{label} excludes unknown properties: #{unknown.join(", ")}" if unknown.any?
      end
      nil
    end

    # @param version [Versponse::Version] version the view belongs to
    # @return [Array<Versponse::Properties::Base>] resolved properties in output order
    # @raise [Versponse::InvalidViewError] when views include each other in a cycle
    def resolve(version)
      apply(version, version.properties.dup, []).values
    end

    # @return [View] self, with operations and properties frozen
    def freeze
      @operations.freeze
      @properties.freeze
      super
    end

    protected

    # @param version [Versponse::Version] version the view belongs to
    # @param result [Hash] properties being built
    # @param chain [Array<Symbol>] views being applied, for cycle detection
    # @return [Hash] result
    def apply(version, result, chain)
      raise InvalidViewError, "include_view cycle in #{version.label}: #{[*chain, name].join(" -> ")}" if chain.include?(name)

      @operations.each do |type, argument|
        case type
        when :add then result[argument] = properties.fetch(argument)
        when :include then version.fetch_view(argument).apply(version, result, [*chain, name])
        when :exclude then argument.each { |key| result.delete(key) }
        end
      end
      result
    end
  end
end
