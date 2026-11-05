# frozen_string_literal: true

require "test_helper"

class ReferenceTest < Minitest::Test
  include ConfigurationTestHelper

  Money = Struct.new(:amount, :currency)
  Site = Struct.new(:id, :name, :unit_types)
  UnitType = Struct.new(:id, :site, :deposit, :prices)
  Price = Struct.new(:id, :amount)
  Category = Struct.new(:name, :children)

  class MoneyResponse < Versponse::Base
    version "2025-01" do
      field :amount, type: :integer
      field :currency, type: :string
    end
  end

  class PriceResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      reference :amount, from: MoneyResponse
    end
  end

  # Declared first so SiteResponse can reference it; Zeitwerk autoloading does this in apps.
  class UnitTypeResponse < Versponse::Base; end

  class SiteResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      field :name, type: :string
      collection :unit_types, item: UnitTypeResponse, view: :embedded

      view :embedded do
        exclude_properties :unit_types
      end
    end
  end

  class UnitTypeResponse
    version "2025-09" do
      field :id, type: :string
      reference :site, from: SiteResponse, view: :embedded
      reference :deposit, from: MoneyResponse, nullable: true
      collection :prices, item: PriceResponse do |unit_type|
        unit_type.prices.reject { |price| price.amount.nil? }
      end

      view :embedded do
        exclude_properties :site
      end
    end
  end

  class CategoryResponse < Versponse::Base
    version "2025-09" do
      field :name, type: :string
      collection :children, item: CategoryResponse
    end
  end

  def money = Money.new(500, "GBP")

  def unit_type(site: Site.new("site_1", "Leeds", []), deposit: money)
    UnitType.new("ut_1", site, deposit, [Price.new("price_1", money), Price.new("price_2", nil)])
  end

  def money_hash = {"amount" => 500, "currency" => "GBP"}

  def test_renders_references_with_views
    expected = {
      "id" => "ut_1",
      "site" => {"id" => "site_1", "name" => "Leeds"},
      "deposit" => money_hash,
      "prices" => [{"id" => "price_1", "amount" => money_hash}]
    }

    assert_equal expected, UnitTypeResponse.serialize(unit_type, version: "2025-09")
  end

  def test_nullable_reference
    assert_nil UnitTypeResponse.serialize(unit_type(deposit: nil), version: "2025-09")["deposit"]
  end

  def test_cycle_is_broken_by_views
    site = Site.new("site_1", "Leeds", [])
    site.unit_types << unit_type(site:)
    rendered = SiteResponse.serialize(site, version: "2026-01")

    assert_equal %w[id deposit prices], rendered["unit_types"].first.keys
  end

  def test_openapi_schema_uses_refs
    properties = UnitTypeResponse.to_schema(version: "2025-09")["properties"]

    assert_equal({"$ref" => "#/components/schemas/SiteResponseEmbedded"}, properties["site"])
    assert_equal({"anyOf" => [{"$ref" => "#/components/schemas/MoneyResponse"}, {"type" => "null"}]}, properties["deposit"])
    assert_equal({"type" => "array", "items" => {"$ref" => "#/components/schemas/PriceResponse"}}, properties["prices"])
  end

  def test_openapi30_nullable_reference
    with_configuration(json_schema_version: :openapi30) do
      expected = {"allOf" => [{"$ref" => "#/components/schemas/MoneyResponse"}], "nullable" => true}

      assert_equal expected, UnitTypeResponse.to_schema(version: "2025-09")["properties"]["deposit"]
    end
  end

  def test_validation_schema_inlines_references
    schema = UnitTypeResponse.to_validation_schema(version: "2025-09")

    assert_equal %w[id name], schema["properties"]["site"]["required"]
    refute schema.key?("$anchor")
  end

  def test_extraction_error_path_crosses_classes
    error = assert_raises(Versponse::ExtractionError) do
      UnitTypeResponse.serialize(unit_type(site: Struct.new(:id).new("site_1")), version: "2025-09")
    end

    assert_match(%r{UnitTypeResponse\[2025-09/default\]\.site\.name: }, error.message)
  end

  def test_recursive_data
    tree = Category.new("Root", [Category.new("Leaf", [])])

    assert_equal({"name" => "Root", "children" => [{"name" => "Leaf", "children" => []}]}, CategoryResponse.serialize(tree, version: "2025-09"))
  end

  def test_recursive_validation_schema_uses_an_anchor
    schema = CategoryResponse.to_validation_schema(version: "2025-09")

    assert_equal "CategoryResponse", schema["$anchor"]
    assert_equal({"$ref" => "#CategoryResponse"}, schema["properties"]["children"]["items"])
  end

  def test_recursive_property_schema_carries_its_own_anchor
    schema = CategoryResponse.to_validation_schema(version: "2025-09", property: :children)

    assert_equal "CategoryResponse", schema["items"]["$anchor"]
    assert_raises(Versponse::PropertyNotFoundError) { CategoryResponse.to_validation_schema(version: "2025-09", property: :missing) }
  end

  module Admin
    class CategoryResponse < Versponse::Base
      # Same component name as ReferenceTest::CategoryResponse
      def self.base_component_name = "CategoryResponse"

      version "2025-09" do
        field :name, type: :string
        reference :public, from: ReferenceTest::CategoryResponse
      end
    end
  end

  def test_classes_sharing_a_component_name_are_not_recursion
    tree = Category.new("Root", [])

    assert_equal({"name" => "Root", "public" => {"name" => "Root", "children" => []}}, Admin::CategoryResponse.serialize({name: "Root", public: tree}, version: "2025-09"))
  end

  def test_definition_errors
    error = assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) { version("2025-09") { reference :amount, from: MoneyResponse, property: :amount, nullable: true } }
    end
    assert_match(/nullable comes from the referenced property/, error.message)
    assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) { version("2025-09") { reference :amount, from: String } }
    end
  end
end
