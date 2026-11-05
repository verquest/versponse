# frozen_string_literal: true

module Versponse
  # Versions of one response class, plus class-level description and schema options
  #
  # @api private
  class Versions
    include Enumerable

    # @return [String, nil] description used by versions that set none
    attr_accessor :description
    # @return [Hash{String => Object}] schema options merged into every version
    attr_accessor :schema_options
    # @return [Array<String>] declared version names, oldest first
    attr_reader :sorted_names

    # @return [Versions] an empty collection
    def initialize
      @versions = {}
      @sorted_names = [].freeze
      @schema_options = {}
      @resolved = Cache.new
    end

    # @param version [Versponse::Version] finalized version
    # @return [void]
    def add(version)
      @versions[version.name] = version
      @sorted_names = @versions.keys.sort.freeze
      Registry.add_version_name(version.name)
      clear_resolved
    end

    # @param name [String] exact declared version name
    # @return [Versponse::Version] the version
    # @raise [Versponse::VersionNotFoundError] when no version has that exact name
    def fetch(name)
      @versions.fetch(name) { raise VersionNotFoundError, "Version #{name} not declared. Declared versions: #{sorted_names.join(", ")}" }
    end

    # @yieldparam version [Versponse::Version]
    # @return [void]
    def each(&)
      @versions.each_value(&)
    end

    # @return [Boolean] true when no version is declared
    def empty?
      @versions.empty?
    end

    # @param name [String] requested version
    # @return [Versponse::Version] closest declared version at or before the request
    # @raise [Versponse::VersionNotFoundError] when there is none
    def resolve(name)
      name = name.to_s
      @resolved.fetch(name) do
        @versions[Versponse.configuration.version_resolver.call(name, sorted_names)] ||
          raise(VersionNotFoundError, "Version #{name} not found. Available versions: #{sorted_names.join(", ")}")
      end
    end

    # @return [void]
    def clear_resolved
      @resolved.clear
    end
  end
end
