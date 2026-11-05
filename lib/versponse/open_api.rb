# frozen_string_literal: true

module Versponse
  # Builds OpenAPI documents from response and request classes, for rswag and other tools
  module OpenAPI
    # @param documents [Array<Class>] Versponse::OpenAPI::Document subclasses
    # @return [Versponse::OpenAPI::RswagSpecs] a drop-in value for rswag's config.openapi_specs
    def self.rswag_specs(*documents)
      RswagSpecs.new(documents)
    end
  end
end
