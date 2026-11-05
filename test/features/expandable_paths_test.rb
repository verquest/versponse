# frozen_string_literal: true

require "test_helper"

class ExpandablePathsTest < Minitest::Test
  include ConfigurationTestHelper

  Stage = Struct.new(:id)
  Deal = Struct.new(:id, :stage)
  Category = Struct.new(:id, :children)
  Unit = Struct.new(:id, :deal, :category, :meta)

  class StageResponse < Versponse::Base
    version "2025-09" do
      identifier :id
      field :id, type: :string
    end
  end

  class DealResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      reference :stage, from: StageResponse, expandable: true
    end
  end

  class CategoryResponse < Versponse::Base
    version "2025-09" do
      identifier :id
      field :id, type: :string
      collection :children, item: CategoryResponse, expandable: true
    end
  end

  class UnitResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      reference :deal, from: DealResponse
      reference :category, from: CategoryResponse, expandable: true
      object :meta do
        reference :stage, from: StageResponse, expandable: true
      end
    end
  end

  def unit = Unit.new("u1", Deal.new("d1", Stage.new("s1")), Category.new("c1", []), {stage: Stage.new("s2")})

  def serialize(expand) = UnitResponse.serialize(unit, version: "2025-09", expand:)

  def test_lists_every_expandable_path
    assert_equal %w[category category.children deal.stage meta.stage], UnitResponse.expandable_paths(version: "2025-09")
  end

  def test_paths_are_cached_and_frozen
    paths = UnitResponse.expandable_paths(version: "2025-09")

    assert_same paths, UnitResponse.expandable_paths(version: "2025-09")
    assert_predicate paths, :frozen?
  end

  def test_unknown_paths_raise_by_default
    error = assert_raises(Versponse::InvalidExpandError) { serialize(%w[deal.stage nope deal]) }

    assert_equal %w[nope deal], error.paths
    assert_match(/Unknown expand paths: nope, deal/, error.message)
  end

  def test_unknown_paths_can_be_ignored
    with_configuration(unknown_expand: :ignore) do
      assert_equal({"id" => "s1"}, serialize(%w[deal.stage nope])["deal"]["stage"])
    end
  end

  def test_deep_paths_of_recursive_classes_are_valid
    tree = Category.new("c1", [Category.new("c2", [Category.new("c3", [])])])
    result = CategoryResponse.serialize(tree, version: "2025-09", expand: ["children.children"])

    assert_equal [{"id" => "c3", "children" => []}], result["children"].first["children"]
  end

  def test_recursive_expandable_schema
    items = CategoryResponse.to_schema(version: "2025-09")["properties"]["children"]["items"]

    assert_equal [{"$ref" => "#/components/schemas/CategoryResponse"}, {"$ref" => "#/components/schemas/CategoryResponseCollapsed"}], items["anyOf"]
  end

  class PlainSiteResponse < Versponse::Base
    version "2025-09" do
      field :site, type: :string
    end
  end

  class ExpandableSiteResponse < Versponse::Base
    version "2025-09" do
      reference :site, from: StageResponse, expandable: true
    end
  end

  class HolderResponse < Versponse::Base
    version "2025-09" do
      one_of :r do
        reference from: PlainSiteResponse, match: ->(object) { object[:kind] == "plain" }
        reference from: ExpandableSiteResponse, match: ->(object) { object[:kind] == "expandable" }
      end
    end
  end

  def test_variants_sharing_a_key
    result = HolderResponse.serialize({r: {kind: "expandable", site: {id: "s1"}}}, version: "2025-09", expand: ["r.site"])

    assert_equal %w[r.site], HolderResponse.expandable_paths(version: "2025-09")
    assert_equal({"site" => {"id" => "s1"}}, result["r"])
  end

  def test_wildcard_is_always_valid
    assert_equal({"id" => "c1", "children" => []}, serialize(["*"])["category"])
  end

  def test_unknown_expand_setting_is_validated
    assert_raises(ArgumentError) { Versponse::Configuration.new.unknown_expand = :maybe }
  end
end
