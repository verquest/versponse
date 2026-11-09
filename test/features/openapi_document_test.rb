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

  class NoteResponse < Versponse::Base
    version "2025-09" do
      identifier :id
      const :object, value: "note"
      field :text, type: :string
    end
  end

  class CallResponse < Versponse::Base
    version "2025-09" do
      identifier :id
      const :object, value: "call"
      field :minutes, type: :integer
    end
  end

  # Every nullable form OpenAPI 3.0 writes, and an object whose properties are all conditional
  class NullableResponse < Versponse::Base
    version "2025-09" do
      reference :note, from: NoteResponse, nullable: true
      reference :linked, from: NoteResponse, nullable: true, expandable: true
      one_of :pinned, nullable: true do
        reference from: NoteResponse, match: ->(value) { value[:object] == "note" }
        reference from: CallResponse, match: ->(value) { value[:object] == "call" }
      end
      one_of :typed, discriminator: "object", nullable: true do
        reference from: NoteResponse, match: ->(value) { value[:object] == "note" }
        reference from: CallResponse, match: ->(value) { value[:object] == "call" }
      end
      object :extra, map: "." do
        field :hint, type: :string, if: ->(_object) { false }
      end
    end
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

  # Like every other schema in the gem; name maps, data keywords and extensions keep their spelling
  def test_hand_written_schemas_are_camelized
    document = Class.new(Versponse::OpenAPI::Document) do
      schema "Note", {
        type: "object", additional_properties: false,
        properties: {due_at: {type: "string", min_length: 1}},
        discriminator: {property_name: "kind", mapping: {unit_type: "#/components/schemas/UnitType"}},
        "x-internal_flag": {keep_me: true},
        enum: [{snake_case: 1}]
      }
    end
    expected = {
      "type" => "object", "additionalProperties" => false,
      "properties" => {"due_at" => {"type" => "string", "minLength" => 1}},
      "discriminator" => {"propertyName" => "kind", "mapping" => {"unit_type" => "#/components/schemas/UnitType"}},
      "x-internal_flag" => {"keep_me" => true},
      "enum" => [{"snake_case" => 1}]
    }

    assert_equal expected, document.build(version: "1")["components"]["schemas"]["Note"]
  end

  def test_subclass_info_merges_over_the_parent
    assert_equal({"version" => "2025-09", "title" => "Sub API", "description" => "Test API"}, build(SubDocument)["info"])
  end

  def test_subclass_info_block_is_resolved_for_the_version
    document = Class.new(ApiDocument) { info { |version| {"summary" => "Built for #{version}"} } }

    assert_equal({"version" => "preview", "title" => "API", "description" => "Test API", "summary" => "Built for preview"}, build(document, version: "preview")["info"])
  end

  # The inheritance table's other rows: these declarations already behave this way
  def test_subclass_replaces_and_appends
    document = Class.new(ApiDocument) do
      external_docs "url" => "https://sub.example.com"
      security []
      server "https://sub.example.com"
      finalize { |built, _version| built["x-sub"] = true }
    end
    built = build(document)

    assert_equal({"url" => "https://sub.example.com"}, built["externalDocs"])
    assert_empty built["security"]
    assert_equal %w[https://api.example.com https://sub.example.com], built["servers"].map { |server| server["url"] }
    assert_equal "2025-09", built["x-built-for"]
    assert built["x-sub"]
  end

  def test_subclass_replaces_named_declarations_in_place
    document = Class.new(ApiDocument) do
      schema "Error", {type: "string"}
      security_scheme "OAuth2", {"type" => "http", "scheme" => "bearer"}
    end
    built = build(document)

    assert_equal %w[Error VersionedError], built["components"]["schemas"].keys
    assert_equal({"type" => "string"}, built["components"]["schemas"]["Error"])
    assert_equal({"type" => "http", "scheme" => "bearer"}, built["components"]["securitySchemes"]["OAuth2"])
  end

  def test_a_class_declares_each_name_once
    %i[schema security_scheme].each do |keyword|
      error = assert_raises(Versponse::DefinitionError) do
        Class.new(Versponse::OpenAPI::Document) do
          send(keyword, "Error", {"type" => "object"})
          send(keyword, "Error", {"type" => "object"})
        end
      end

      assert_equal "#{keyword} Error is declared twice", error.message
    end
  end

  def test_versions_reads_without_arguments
    assert_equal %w[2025-09 preview], ApiDocument.versions
    assert_equal %w[2025-09 preview], ApiDocument.document_versions
  end

  def test_subclass_versions_replace_the_parent
    document = Class.new(ApiDocument) { versions "2026-01" }

    assert_equal ["2026-01"], document.versions
    assert_equal %w[2025-09 preview], ApiDocument.versions
  end

  def test_finalize_block_may_take_only_the_document
    document = Class.new(Versponse::OpenAPI::Document) { finalize(&->(built) { built["x-one"] = true }) }

    assert document.build(version: "1")["x-one"]
  end

  def test_server_and_tag_extensions
    document = Class.new(Versponse::OpenAPI::Document) do
      server "https://internal.example.com", x_internal: true
      tag "Admin", x_display_name: "Administration"
    end
    built = document.build(version: "1")

    assert_equal [{"url" => "https://internal.example.com", "x-internal" => true}], built["servers"]
    assert_equal [{"name" => "Admin", "x-display-name" => "Administration"}], built["tags"]
  end

  # Strict 3.0 validators ignore nullable beside a combinator, so null is a branch of its own
  def test_openapi30_documents_validate_and_accept_null
    with_configuration(json_schema_version: :openapi30) do
      document = Class.new(Versponse::OpenAPI::Document) do
        info "title" => "API"
        responses NullableResponse, NoteResponse, CallResponse
      end

      assert_empty document.validate(version: "2025-09")

      require "json_schemer"
      schemer = JSONSchemer.openapi(document.build(version: "2025-09")).schema("NullableResponse")
      nulls = {"note" => nil, "linked" => nil, "pinned" => nil, "typed" => nil, "extra" => {}}

      assert_empty schemer.validate(nulls).map { |error| error["error"] }
      %w[note linked pinned typed].each do |key|
        refute schemer.valid?(nulls.merge(key => 1)), "#{key} accepts 1"
      end
    end
  end

  # Response components are the classes' frozen, cached schemas; build hands out a copy, with or without finalize hooks
  def test_built_documents_are_the_callers_to_change
    document = Class.new(Versponse::OpenAPI::Document) do
      info "title" => "API"
      responses NoteResponse
    end
    built = document.build(version: "2025-09")

    built["components"]["schemas"]["NoteResponse"]["description"] = "Changed"

    refute document.build(version: "2025-09")["components"]["schemas"]["NoteResponse"].key?("description")
  end
end
