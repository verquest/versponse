# frozen_string_literal: true

module Versponse
  # Builds the components/schemas hash of an OpenAPI document for one version
  #
  # @api private
  module Components
    # @param version [String] requested version
    # @param classes [Array<Class>] response classes
    # @return [Hash{String => Hash}] schemas keyed by component name, one per class and view
    # @raise [Versponse::DefinitionError] when two components share a name
    def self.call(version:, classes:)
      classes.each_with_object({}) do |klass, components|
        definition = resolved(klass, version)
        next unless definition

        definition.view_names.each do |view|
          name = klass.component_name(view:)
          raise DefinitionError, "Duplicate component name #{name} (#{klass.name || klass.inspect})" if components.key?(name)

          components[name] = klass.to_schema(version:, view:)
        end
      end
    end

    # @param klass [Class] response class
    # @param version [String] requested version
    # @return [Versponse::Version, nil] the resolved version, nil when the class does not cover it
    def self.resolved(klass, version)
      return if klass.versions.empty?

      klass.resolve(version)
    rescue VersionNotFoundError
      nil
    end
  end
end
