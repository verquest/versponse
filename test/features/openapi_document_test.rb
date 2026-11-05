# frozen_string_literal: true

require "test_helper"

class OpenapiDocumentTest < Minitest::Test
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
  end

  class SubDocument < ApiDocument
    document_name "sub"
    info "title" => "Sub API"
    tag "Extra"
  end

  def build(document = ApiDocument, version: "2025-09") = document.build(version:)

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

  def test_info_needs_a_value
    assert_raises(Versponse::DefinitionError) { Class.new(Versponse::OpenAPI::Document) { info } }
  end
end
