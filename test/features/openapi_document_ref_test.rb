# frozen_string_literal: true

require "test_helper"

class OpenapiDocumentRefTest < Minitest::Test
  class SiteResponse < Versponse::Base
    version "2025-09" do
      identifier :id
    end
  end

  class ApiDocument < Versponse::OpenAPI::Document
    wrapper :site_list, SiteResponse, root: "sites", collection: true
    wrapper "SiteSingle", SiteResponse, root: "site"
    schema :error, {type: "object"}
    schema "UnitOverlockSuccess", {type: "object"}
  end

  class SubDocument < ApiDocument
    wrapper :site_page, SiteResponse, root: "sites", collection: true
  end

  def test_symbols_are_pascalized_like_wrapper_names
    assert_equal "SiteList", ApiDocument.component_name(:site_list)
    assert_equal "#/components/schemas/SiteList", ApiDocument.ref(:site_list)
  end

  def test_pascal_case_and_snake_case_symbols_name_the_same_component
    assert_equal ApiDocument.ref(:site_list), ApiDocument.ref(:SiteList)
    assert_equal "#/components/schemas/SiteSingle", ApiDocument.ref(:SiteSingle)
    assert_equal "#/components/schemas/UnitOverlockSuccess", ApiDocument.ref(:UnitOverlockSuccess)
  end

  def test_strings_are_used_as_given
    assert_equal "SiteSingle", ApiDocument.component_name("SiteSingle")
    assert_equal "#/components/schemas/UnitOverlockSuccess", ApiDocument.ref("UnitOverlockSuccess")
  end

  def test_schemas_are_referenced_by_their_declared_name
    assert_equal "#/components/schemas/error", ApiDocument.ref("error")
    assert_raises(Versponse::DefinitionError) { ApiDocument.ref(:error) }
  end

  def test_subclasses_reference_inherited_declarations
    assert_equal "#/components/schemas/SiteList", SubDocument.ref(:site_list)
    assert_equal "#/components/schemas/SitePage", SubDocument.ref(:site_page)
    assert_raises(Versponse::DefinitionError) { ApiDocument.ref(:site_page) }
  end

  def test_unknown_names_raise
    error = assert_raises(Versponse::DefinitionError) { ApiDocument.ref(:site_lsit) }

    assert_equal "OpenapiDocumentRefTest::ApiDocument declares no wrapper or schema :site_lsit (SiteLsit)", error.message
  end

  def test_unknown_string_names_name_the_string
    error = assert_raises(Versponse::DefinitionError) { ApiDocument.component_name("SiteLsit") }

    assert_equal "OpenapiDocumentRefTest::ApiDocument declares no wrapper or schema \"SiteLsit\"", error.message
  end
end
