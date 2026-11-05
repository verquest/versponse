# frozen_string_literal: true

module Versponse
  # Resolves a requested version to the closest declared version at or before it
  # Versions are compared as Strings, so they must sort lexicographically (dates like YYYY-MM do).
  # A custom resolver must keep this closest-earlier behaviour, because requested versions are
  # canonicalized against every declared name before caching.
  #
  # @example
  #   Versponse::VersionResolver.call("2025-04", %w[2025-01 2025-06]) # => "2025-01"
  class VersionResolver
    # @param requested_version [String] version asked for
    # @param versions [Array<String>] declared versions, oldest first
    # @return [String, nil] the resolved version, or nil when the request is older than every version
    def self.call(requested_version, versions)
      versions.reverse_each.find { |version| version <= requested_version }
    end
  end
end
