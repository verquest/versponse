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

    # @param owner [String] response class name, for messages
    # @return [Versions] an empty collection
    def initialize(owner: "AnonymousResponse")
      @owner = owner
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

    # Resolutions are memoized by name, so pass the class's own range on every call
    # (supported_versions clears the memo through Versponse.reset_caches!). Raising stores nothing.
    #
    # @param name [String] requested version
    # @param supported [Versponse::SupportedVersions, nil] range declared with supported_versions
    # @return [Versponse::Version] closest declared version at or before the request
    # @raise [Versponse::VersionNotFoundError] when there is none, or the range leaves the request out
    # @raise [Versponse::DefinitionError] when the range's max sorts before every declared version
    def resolve(name, supported: nil)
      name = name.to_s
      @resolved.fetch(name) do
        raise VersionNotFoundError, "Version #{name} is outside supported_versions (#{supported}) of #{@owner}" if supported && !supported?(canonical_name(name), supported)

        @versions[Versponse.configuration.version_resolver.call(name, sorted_names)] ||
          raise(VersionNotFoundError, "Version #{name} not found. Available versions: #{sorted_names.join(", ")}")
      end
    end

    # Checks the requested name only; declared blocks may lie outside the range
    #
    # @param name [String] requested version name
    # @param supported [Versponse::SupportedVersions, nil] range declared with supported_versions
    # @return [Boolean] true without a range or declared versions, otherwise whether the range includes name
    # @raise [Versponse::DefinitionError] when the range's max sorts before every declared version
    def supported?(name, supported)
      return true if supported.nil? || empty?

      supported.check!(sorted_names, @owner)
      supported.covers?(name)
    end

    # Names eager_load! compiles: the declared versions inside the range plus min (so a min: "preview"
    # class whose only block is 2025-09 compiles that block as "preview"), canonicalized like serialize
    # does, keeping those that resolve to a declared version
    #
    # @param supported [Versponse::SupportedVersions, nil] range declared with supported_versions
    # @return [Array<String>] canonical version names
    # @raise [Versponse::DefinitionError] when the range's max sorts before every declared version
    def supported_names(supported)
      return sorted_names if supported.nil? || empty?

      supported.check!(sorted_names, @owner)
      candidates = [*sorted_names, supported.min].compact.map { |name| canonical_name(name) }.uniq
      candidates.select { |name| supported.covers?(name) && Versponse.configuration.version_resolver.call(name, sorted_names) }
    end

    # @return [void]
    def clear_resolved
      @resolved.clear
    end

    private

    # The name serialize and to_schema cache under, so resolve("2026-04") and serialize(version: "2026-04") agree
    def canonical_name(name)
      Registry.canonical(name)
    end
  end
end
