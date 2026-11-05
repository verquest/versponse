# frozen_string_literal: true

module Examples
  class PublicApiDocument < Versponse::OpenAPI::Document
    document_name "public_api"
    versions "2025-09", "2026-03"
    info "title" => "Example Public API", "description" => "Stora-shaped example"
    external_docs { |version| {"url" => "https://docs.example.com/#{version}/"} }
    server "https://api.example.com", description: "Production"
    tag "Unit Types", description: "Unit types"
    security_scheme "OAuth2" do
      {"type" => "oauth2", "flows" => {"clientCredentials" => {"tokenUrl" => "https://api.example.com/oauth2/token", "scopes" => {"unit_types:read" => "Read unit types"}}}}
    end
    security [{"OAuth2" => ["unit_types:read"]}]

    responses namespace: "Examples"
    wrapper :unit_type_list, UnitTypeResponse, root: "unit_types", collection: true, meta: MetaResponse
    wrapper :unit_type_single, UnitTypeResponse, root: "unit_type", meta: MetaResponse
    schema "Error", {
      "type" => "object", "additionalProperties" => false,
      "properties" => {"error" => {"type" => "object", "properties" => {"code" => {"type" => "string"}, "message" => {"type" => "string"}}}}
    }
    webhooks do |version|
      {"unit_type.updated" => {"post" => {"summary" => "Unit type updated (#{version})", "responses" => {"200" => {"description" => "Received"}}}}}
    end
  end
end
