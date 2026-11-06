# frozen_string_literal: true

require "test_helper"
require "verquest"

class OpenapiComponentsTest < Minitest::Test
  module Api
    class SiteResponse < Versponse::Base
      version "2025-09" do
        identifier :id
        field :name, type: :string
      end
    end

    class MetaResponse < Versponse::Base
      version "2025-09" do
        field :request_id, type: :string
      end
    end

    class FutureResponse < Versponse::Base
      version "2026-01" do
        field :id, type: :string
      end
    end

    class SiteCreateRequest < Verquest::Base
      version "2025-06" do
        field :name, type: :string, required: true
      end
    end

    class SiteSearchRequest < Verquest::Base
      location :query
      version "2025-06" do
        field :page, type: :integer
      end
    end
  end

  # Outside the Api namespace; its reference to Api::SiteResponse dangles in a document without it
  module Elsewhere
    class OwnerResponse < Versponse::Base
      version "2025-09" do
        field :id, type: :string
        reference :site, from: Api::SiteResponse
      end
    end

    # Its property is named like a data keyword, which must not hide the reference
    class DefaultResponse < Versponse::Base
      version "2025-09" do
        reference :default, from: Api::SiteResponse
      end
    end
  end

  class ApiDocument < Versponse::OpenAPI::Document
    info "title" => "API"
    responses namespace: "OpenapiComponentsTest::Api"
    requests namespace: "OpenapiComponentsTest::Api"
    wrapper :site_list, Api::SiteResponse, root: "sites", collection: true, meta: Api::MetaResponse
  end

  def schemas(document = ApiDocument, version: "2025-09") = document.build(version:)["components"]["schemas"]

  def test_collects_responses_requests_and_wrappers
    expected = %w[ApiMetaResponse ApiSiteCreateRequest ApiSiteResponse ApiSiteResponseCollapsed site_list]

    assert_equal expected, schemas.keys.sort
  end

  def test_component_schemas
    assert_equal Api::SiteResponse.to_schema(version: "2025-09"), schemas["ApiSiteResponse"]
    assert_equal Api::SiteCreateRequest.to_schema(version: "2025-09"), schemas["ApiSiteCreateRequest"]
    assert_equal Api::SiteResponse.to_schema(version: "2025-09", root: "sites", collection: true, meta: Api::MetaResponse), schemas["site_list"]
  end

  def test_later_versions_add_classes
    assert_includes schemas(version: "2026-02").keys, "ApiFutureResponse"
  end

  def test_classes_without_the_version_are_skipped
    document = Class.new(Versponse::OpenAPI::Document) do
      responses namespace: "OpenapiComponentsTest::Api"
      requests namespace: "OpenapiComponentsTest::Api"
    end

    assert_empty schemas(document, version: "2025-01")
  end

  def test_explicit_lists
    document = Class.new(Versponse::OpenAPI::Document) do
      info "title" => "API"
      responses [Api::MetaResponse]
      requests [Api::SiteCreateRequest]
    end

    assert_equal %w[ApiMetaResponse ApiSiteCreateRequest], schemas(document).keys.sort
  end

  # Hooks get a copy, so they can change components without touching the classes' cached schemas
  def test_finalize_hooks_can_change_components
    document = Class.new(Versponse::OpenAPI::Document) do
      info "title" => "API"
      responses [Api::MetaResponse]
      finalize { |built, _version| built["components"]["schemas"]["ApiMetaResponse"]["x-tag"] = "meta" }
    end

    assert_equal "meta", schemas(document)["ApiMetaResponse"]["x-tag"]
    refute Api::MetaResponse.to_schema(version: "2025-09").key?("x-tag")
  end

  def test_validate_reports_dangling_refs
    document = Class.new(Versponse::OpenAPI::Document) do
      info "title" => "API"
      responses [Elsewhere::OwnerResponse]
    end
    errors = document.validate(version: "2025-09")
    error = errors.first

    assert_equal 1, errors.size
    assert_equal "/components/schemas/ElsewhereOwnerResponse/properties/site", error[:pointer]
    assert_equal "ref", error[:type]
    assert_equal "$ref #/components/schemas/ApiSiteResponse does not resolve in the document", error[:message]
  end

  def test_validate_checks_refs_under_any_property_name_mappings_and_examples
    document = Class.new(Versponse::OpenAPI::Document) do
      info "title" => "API"
      responses [Elsewhere::DefaultResponse]
      schema "Poly", {"type" => "object", "discriminator" => {"propertyName" => "t", "mapping" => {"x" => "#/components/schemas/Missing"}}}
      finalize do |built, _version|
        built["paths"]["/x"] = {"get" => {"responses" => {"200" => {"description" => "ok", "content" => {"application/json" => {
          "examples" => {"a" => {"$ref" => "#/components/examples/Missing"}}
        }}}}}}
      end
    end

    refs = document.validate(version: "2025-09").select { |error| error[:type] == "ref" }.map { |error| error[:details]["ref"] }

    assert_equal %w[#/components/examples/Missing #/components/schemas/ApiSiteResponse #/components/schemas/Missing], refs.sort
  end

  def test_schema_collisions_raise
    document = Class.new(ApiDocument) { schema "ApiMetaResponse", {"type" => "object"} }

    error = assert_raises(Versponse::DefinitionError) { schemas(document) }

    assert_equal "Component ApiMetaResponse from schema ApiMetaResponse collides with OpenapiComponentsTest::Api::MetaResponse", error.message
  end

  def test_collisions_raise
    document = Class.new(ApiDocument) { wrapper :ApiSiteResponse, Api::SiteResponse, root: "site" }

    error = assert_raises(Versponse::DefinitionError) { schemas(document) }

    assert_equal "Component ApiSiteResponse from wrapper ApiSiteResponse collides with OpenapiComponentsTest::Api::SiteResponse", error.message
  end
end
