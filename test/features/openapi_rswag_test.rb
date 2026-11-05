# frozen_string_literal: true

require "test_helper"

class OpenapiRswagTest < Minitest::Test
  class ApiDocument < Versponse::OpenAPI::Document
    document_name "api"
    versions "2025-09", "preview"
    info "title" => "API"
  end

  class BrokenDocument < Versponse::OpenAPI::Document
    info "title" => "Broken"
    finalize { |document, _version| document["info"].delete("version") }
  end

  def specs = Versponse::OpenAPI.rswag_specs(ApiDocument)

  def test_keys_and_values
    assert_equal %w[api/2025-09.json api/preview.json], specs.keys
    assert_equal 2, specs.values.size
    refute_predicate specs, :empty?
  end

  def test_documents_are_symbol_keyed_and_memoized
    adapter = specs
    document = adapter["api/2025-09.json"]

    assert_equal "3.1.1", document[:openapi]
    assert_equal "2025-09", document[:info][:version]
    assert_same document, adapter["api/2025-09.json"]
  end

  def test_yaml_keys_and_unknown_keys
    adapter = specs

    assert_same adapter["api/preview.json"], adapter["api/preview.yaml"]
    assert_nil adapter["api/2024-01.json"]
    assert_raises(KeyError) { adapter.fetch("api/2024-01.json") }
  end

  def test_each_yields_every_document
    assert_equal %w[api/2025-09.json api/preview.json], specs.map { |key, _document| key }
  end

  def test_document_name_is_required
    assert_raises(Versponse::DefinitionError) { Versponse::OpenAPI.rswag_specs(BrokenDocument) }
  end

  def test_validate
    assert_empty ApiDocument.validate(version: "2025-09")

    error = BrokenDocument.validate(version: "1").first

    assert_equal "/info", error[:pointer]
    assert_equal "required", error[:type]
  end
end
