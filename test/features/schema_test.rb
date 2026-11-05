# frozen_string_literal: true

require "test_helper"

class SchemaTest < Minitest::Test
  include ConfigurationTestHelper

  class ProductResponse < Versponse::Base
    description "A product"

    version "2025-09" do
      field :id, type: :string, description: "Product ID"
      field :price, type: :integer, nullable: true
      field :discount, type: :integer, if: ->(product) { product[:discount] }

      view :compact do
        exclude_properties :price
      end
    end

    version "2026-01" do
      description "A product, v2"
      schema_options deprecated: true
    end
  end

  class RenamedResponse < Versponse::Base
    def self.base_component_name = super.delete_suffix("Response")

    version "2025-09" do
      field :id, type: :string
    end
  end

  module Nested
    class DeepResponse < Versponse::Base
      version "2025-09" do
        field :id, type: :string
      end
    end
  end

  def test_to_schema
    expected = {
      "type" => "object",
      "description" => "A product",
      "required" => %w[id price],
      "properties" => {
        "id" => {"type" => "string", "description" => "Product ID"},
        "price" => {"type" => %w[integer null]},
        "discount" => {"type" => "integer"}
      },
      "additionalProperties" => false
    }

    assert_equal expected, ProductResponse.to_schema(version: "2025-09")
  end

  def test_view_schema
    schema = ProductResponse.to_schema(version: "2025-09", view: :compact)

    assert_equal %w[id], schema["required"]
    assert_equal %w[id discount], schema["properties"].keys
  end

  def test_version_description_and_schema_options
    schema = ProductResponse.to_schema(version: "2026-01")

    assert_equal "A product, v2", schema["description"]
    assert schema["deprecated"]
  end

  def test_openapi30_nullable
    with_configuration(json_schema_version: :openapi30) do
      assert_equal({"type" => "integer", "nullable" => true}, ProductResponse.to_schema(version: "2025-09")["properties"]["price"])
    end
  end

  def test_component_names
    assert_equal "ProductResponse", ProductResponse.component_name
    assert_equal "ProductResponseCompact", ProductResponse.component_name(view: :compact)
    assert_equal "Renamed", RenamedResponse.component_name
    assert_equal "NestedDeepResponse", Nested::DeepResponse.component_name
  end

  def test_to_ref
    assert_equal "#/components/schemas/ProductResponseCompact", ProductResponse.to_ref(view: :compact)
    assert_equal "#/components/schemas/ProductResponse/properties/id", ProductResponse.to_ref(property: :id)
  end

  def test_validation_schema
    assert_equal ProductResponse.to_schema(version: "2025-09"), ProductResponse.to_validation_schema(version: "2025-09")
    assert_equal({"type" => "string", "description" => "Product ID"}, ProductResponse.to_validation_schema(version: "2025-09", property: :id))
  end

  def test_schemas_are_cached_and_deeply_frozen
    schema = ProductResponse.to_schema(version: "2025-09")

    assert_same schema, ProductResponse.to_schema(version: "2025-09")
    assert_predicate schema["properties"]["id"], :frozen?
  end
end
