# frozen_string_literal: true

require "test_helper"

class RootMetaTest < Minitest::Test
  class MetaResponse < Versponse::Base
    version "2025-09" do
      field :request_id, type: :string
    end
  end

  class ItemResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
    end
  end

  def test_meta_requires_root
    error = assert_raises(ArgumentError) { ItemResponse.to_schema(version: "2025-09", meta: MetaResponse) }

    assert_equal "meta: requires root:", error.message
  end

  def test_wrapper_schema_is_frozen
    assert_predicate ItemResponse.to_schema(version: "2025-09", root: :item)["properties"], :frozen?
  end

  def test_wrapper_schema
    expected = {
      "type" => "object",
      "required" => %w[item meta],
      "properties" => {
        "item" => {"$ref" => "#/components/schemas/ItemResponse"},
        "meta" => {"$ref" => "#/components/schemas/MetaResponse"}
      },
      "additionalProperties" => false
    }

    assert_equal expected, ItemResponse.to_schema(version: "2025-09", root: :item, meta: MetaResponse)
  end

  def test_collection_wrapper_schema
    expected = {
      "type" => "object",
      "required" => ["items"],
      "properties" => {"items" => {"type" => "array", "items" => {"$ref" => "#/components/schemas/ItemResponse"}}},
      "additionalProperties" => false
    }

    assert_equal expected, ItemResponse.to_schema(version: "2025-09", root: "items", collection: true)
  end
end
