# frozen_string_literal: true

module Versponse
  # Inclusive range of versions a response class serves, declared with supported_versions.
  # Versions are compared with config.version_resolver, so the range uses the same order as
  # resolution (string order by default, where "preview" sorts after dated versions).
  #
  # @api private
  class SupportedVersions
    # @return [String, nil] first supported version, nil to start at the first declared version
    attr_reader :min
    # @return [String, nil] last supported version, nil for no upper bound
    attr_reader :max

    # The resolver picks earlier for a request of later only when earlier sorts at or before it
    #
    # @param earlier [String] version expected first
    # @param later [String] version expected second
    # @return [Boolean] true when earlier sorts at or before later
    def self.at_or_before?(earlier, later)
      Versponse.configuration.version_resolver.call(later, [earlier]) == earlier
    end

    # @param min [String, nil] first supported version (inclusive)
    # @param max [String, nil] last supported version (inclusive)
    # @raise [Versponse::DefinitionError] when min sorts after max
    def initialize(min:, max:)
      @min = min&.to_s
      @max = max&.to_s
      raise DefinitionError, "supported_versions min: #{@min} is after max: #{@max}" if @min && @max && !self.class.at_or_before?(@min, @max)

      freeze
    end

    # Without min, earlier versions are left to the resolver, which finds nothing before the first declared one
    #
    # @param version [String] version name
    # @return [Boolean] true when the range includes the version
    def covers?(version)
      (min.nil? || self.class.at_or_before?(min, version)) && (max.nil? || self.class.at_or_before?(version, max))
    end

    # Only max is checked: declared blocks don't have to be inside the range, so min: "preview"
    # with a single version "2025-09" block serves "preview" from 2025-09
    #
    # @param declared [Array<String>] declared version names, oldest first
    # @param owner [String] class name, for the message
    # @return [void]
    # @raise [Versponse::DefinitionError] when max sorts before every declared version, so no request could resolve
    def check!(declared, owner)
      return if max.nil? || declared.empty? || declared.any? { |version| self.class.at_or_before?(version, max) }

      raise DefinitionError, "#{owner}: supported_versions max: #{max} is before every declared version (#{declared.join(", ")})"
    end

    # @return [String] the range for messages, like "min: 2025-09, max: none"
    def to_s
      "min: #{min || "first declared"}, max: #{max || "none"}"
    end
  end
end
