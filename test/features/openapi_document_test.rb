# frozen_string_literal: true

require "test_helper"

class OpenapiDocumentTest < Minitest::Test
  include ConfigurationTestHelper

  class ApiDocument < Versponse::OpenAPI::Document
    document_name "api"
    versions "2025-09", "preview"
    info "title" => "API", "description" => "Test API"
    external_docs { |version| {"url" => "https://docs.example.com/#{version}/"} }
    server "https://api.example.com", description: "Production"
    tag "Sites", description: "Sites"
    security_scheme "OAuth2" do
      {"type" => "oauth2", "flows" => {"clientCredentials" => {"tokenUrl" => "https://api.example.com/oauth2/token", "scopes" => {"sites:read" => "Read sites"}}}}
    end
    security [{"OAuth2" => []}]
    finalize { |document, version| document["x-built-for"] = version }
    schema "Error", {type: "object", properties: {message: {type: "string"}}}
    schema("VersionedError") { |version| {"type" => "object", "description" => "Error in #{version}"} }
    webhooks { |version| {"site.created" => {"post" => {"summary" => "Site created (#{version})"}}} }
  end

  class SubDocument < ApiDocument
    document_name "sub"
    info "title" => "Sub API"
    tag "Extra"
    webhooks "site.deleted" => {"post" => {"summary" => "Site deleted"}}
  end

  def build(document = ApiDocument, version: "2025-09") = document.build(version:)

  def test_openapi_version_follows_the_configured_schema_version
    document = Class.new(Versponse::OpenAPI::Document) { info "title" => "No webhooks" }

    with_configuration(json_schema_version: :openapi30) do
      assert_equal "3.0.3", document.build(version: "2025-09")["openapi"]
    end
  end

  # OpenAPI 3.0 has no webhooks section
  def test_webhooks_raise_in_openapi30
    with_configuration(json_schema_version: :openapi30) do
      error = assert_raises(Versponse::DefinitionError) { build }

      assert_equal "webhooks need OpenAPI 3.1 (config.json_schema_version is :openapi30)", error.message
    end
  end

  def test_declared_openapi_version_must_match_the_configured_schema_version
    document = Class.new(Versponse::OpenAPI::Document) { openapi "3.0.3" }

    error = assert_raises(Versponse::DefinitionError) { document.build(version: "2025-09") }

    assert_equal "openapi 3.0.3 doesn't match config.json_schema_version :openapi31 (use 3.1.x)", error.message
  end

  def test_base_sections
    document = build

    assert_equal "3.1.1", document["openapi"]
    assert_equal({"version" => "2025-09", "title" => "API", "description" => "Test API"}, document["info"])
    assert_equal({"url" => "https://docs.example.com/2025-09/"}, document["externalDocs"])
    assert_equal [{"url" => "https://api.example.com", "description" => "Production"}], document["servers"]
    assert_equal [{"name" => "Sites", "description" => "Sites"}], document["tags"]
    assert_equal [{"OAuth2" => []}], document["security"]
  end

  def test_paths_and_security_schemes
    document = build

    assert_empty document["paths"]
    assert_equal({"sites:read" => "Read sites"}, document["components"]["securitySchemes"]["OAuth2"]["flows"]["clientCredentials"]["scopes"])
  end

  def test_finalize_hooks_run_last
    assert_equal "preview", build(version: "preview")["x-built-for"]
  end

  def test_unknown_version_raises
    assert_raises(ArgumentError) { build(version: "2024-01") }
  end

  def test_subclasses_inherit_and_override
    document = build(SubDocument)

    assert_equal "Sub API", document["info"]["title"]
    assert_equal [{"name" => "Sites", "description" => "Sites"}, {"name" => "Extra"}], document["tags"]
    assert_equal "sub", SubDocument.document_name
    assert_equal "api", ApiDocument.document_name
  end

  def test_minimal_document_omits_undeclared_sections
    document = Class.new(Versponse::OpenAPI::Document) { info "title" => "Min" }.build(version: "1")

    assert_equal %w[openapi info paths components], document.keys
    assert_equal({"schemas" => {}}, document["components"])
  end

  def test_hand_written_schemas
    schemas = build(version: "preview")["components"]["schemas"]

    assert_equal({"type" => "object", "properties" => {"message" => {"type" => "string"}}}, schemas["Error"])
    assert_equal "Error in preview", schemas["VersionedError"]["description"]
  end

  def test_webhooks_follow_paths
    document = build

    assert_equal %w[paths webhooks components], document.keys.drop_while { |key| key != "paths" }.first(3)
    assert_equal "Site created (2025-09)", document["webhooks"]["site.created"]["post"]["summary"]
    assert_equal ["site.deleted"], build(SubDocument)["webhooks"].keys
  end

  def test_schema_and_webhooks_need_a_value
    assert_raises(Versponse::DefinitionError) { Class.new(Versponse::OpenAPI::Document) { schema "Error" } }
    assert_raises(Versponse::DefinitionError) { Class.new(Versponse::OpenAPI::Document) { webhooks } }
  end

  def test_info_needs_a_value
    assert_raises(Versponse::DefinitionError) { Class.new(Versponse::OpenAPI::Document) { info } }
  end
end
