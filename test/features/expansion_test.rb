# frozen_string_literal: true

require "test_helper"

class ExpansionTest < Minitest::Test
  Site = Struct.new(:public_id, :name)
  Price = Struct.new(:id, :amount)
  Deal = Struct.new(:id, :stage)
  Stage = Struct.new(:id, :name)
  Unit = Struct.new(:id, :site, :backup_site, :prices, :deal)

  class SiteResponse < Versponse::Base
    version "2025-09" do
      identifier :id, map: "public_id"
      field :name, type: :string
    end
  end

  class PriceResponse < Versponse::Base
    version "2025-09" do
      identifier :id
      field :amount, type: :integer
    end
  end

  class StageResponse < Versponse::Base
    version "2025-09" do
      identifier :id
      field :name, type: :string
    end
  end

  class DealResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      reference :stage, from: StageResponse, expandable: true
    end
  end

  class UnitResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      reference :site, from: SiteResponse, expandable: true
      reference :backup_site, from: SiteResponse, expandable: true, nullable: true
      collection :prices, item: PriceResponse, expandable: true
      reference :deal, from: DealResponse
    end
  end

  class PlainResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
    end
  end

  class Foreign
    def self.to_ref(property: nil) = "#/components/schemas/Foreign"

    def self.to_validation_schema(version:, property: nil) = {"type" => "object"}
  end

  def unit = Unit.new("u1", Site.new("site_1", "Leeds"), nil, [Price.new("p1", 5)], Deal.new("d1", Stage.new("s1", "Won")))

  def serialize(expand: nil) = UnitResponse.serialize(unit, version: "2025-09", expand:)

  def define(&) = Class.new(Versponse::Base) { version("2025-09", &) }

  def ref(name) = {"$ref" => "#/components/schemas/#{name}"}

  def test_collapsed_by_default
    expected = {
      "id" => "u1", "site" => {"id" => "site_1"}, "backup_site" => nil,
      "prices" => [{"id" => "p1"}], "deal" => {"id" => "d1", "stage" => {"id" => "s1"}}
    }

    assert_equal expected, serialize
  end

  def test_expanding_paths
    result = serialize(expand: %w[site prices])

    assert_equal({"id" => "site_1", "name" => "Leeds"}, result["site"])
    assert_equal [{"id" => "p1", "amount" => 5}], result["prices"]
  end

  def test_path_through_a_non_expandable_association
    assert_equal({"id" => "s1", "name" => "Won"}, serialize(expand: ["deal.stage"])["deal"]["stage"])
  end

  def test_wildcard_expands_everything
    result = serialize(expand: ["*"])

    assert_equal "Leeds", result["site"]["name"]
    assert_equal "Won", result["deal"]["stage"]["name"]
  end

  def test_to_json_passes_expand
    assert_equal "Leeds", JSON.parse(UnitResponse.serialize_json(unit, version: "2025-09", expand: [:site]))["site"]["name"]
  end

  def test_openapi_schema
    properties = UnitResponse.to_schema(version: "2025-09")["properties"]

    assert_equal({"anyOf" => [ref("SiteResponse"), ref("SiteResponseCollapsed")]}, properties["site"])
    assert_equal({"anyOf" => [ref("SiteResponse"), ref("SiteResponseCollapsed"), {"type" => "null"}]}, properties["backup_site"])
    assert_equal({"type" => "array", "items" => {"anyOf" => [ref("PriceResponse"), ref("PriceResponseCollapsed")]}}, properties["prices"])
  end

  def test_validation_schema_inlines_both_shapes
    site = UnitResponse.to_validation_schema(version: "2025-09")["properties"]["site"]

    assert_equal [%w[id name], %w[id]], site["anyOf"].map { |schema| schema["required"] }
  end

  def test_missing_identifier_raises
    klass = define { reference :plain, from: PlainResponse, expandable: true }

    assert_raises(Versponse::DefinitionError) { klass.serialize({plain: {id: "x"}}, version: "2025-09") }
    assert_raises(Versponse::DefinitionError) { klass.to_schema(version: "2025-09") }
    assert_raises(Versponse::DefinitionError) { klass.to_validation_schema(version: "2025-09") }
    assert_raises(Versponse::DefinitionError) { Versponse.components(version: "2025-09", classes: [klass]) }
  end

  def test_misplaced_expandable_raises
    assert_raises(Versponse::DefinitionError) { define { field :a, type: :string, expandable: true } }
    assert_raises(Versponse::DefinitionError) { define { object(:a, expandable: true) { field :b, type: :string } } }
    assert_raises(Versponse::DefinitionError) { define { collection(:a, expandable: true) { field :b, type: :string } } }
    assert_raises(Versponse::DefinitionError) { define { reference :a, from: Foreign, expandable: true } }
    assert_raises(Versponse::DefinitionError) { define { reference :a, from: SiteResponse, property: :name, expandable: true } }
    assert_raises(Versponse::DefinitionError) { define { collection :a, item: Foreign, expandable: true } }
  end

  class DescribedResponse < Versponse::Base
    description "A described resource"
    schema_options min_properties: 2

    version "2025-09" do
      identifier :id
      field :x, type: :string
    end
  end

  def test_collapsed_output_validates_against_a_described_class
    klass = define { reference :described, from: DescribedResponse, expandable: true }

    assert_equal({"described" => {"id" => "d1"}}, klass.serialize({described: {id: "d1", x: "y"}}, version: "2025-09"))
  end
end
