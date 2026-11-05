# frozen_string_literal: true

require "test_helper"

class SerializeTest < Minitest::Test
  include ConfigurationTestHelper

  UnitType = Struct.new(:public_id, :name, :billing_id, :status, :selling_points, :created_at, :secret, :discount)

  class UnitTypeResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string, map: "public_id"
      field :name, type: :string
      field :stripe_product_id, type: :string, map: "billing_id", nullable: true
      enum :status, type: :string, values: %w[active archived]
      array :selling_points, type: :string
      field :created_at, type: :string, format: "date-time"
      field :secret, type: :string, nullable: true do |unit_type, context|
        context[:show_secret] ? unit_type[:secret] : nil
      end
      field :discount, type: :integer, if: ->(unit_type) { unit_type[:discount] }
      const :object, value: "unit_type"
    end
  end

  def unit_type(**overrides)
    UnitType.new(
      public_id: "ut_1", name: "Small", billing_id: nil, status: "active", selling_points: ["Dry"],
      created_at: Time.utc(2025, 9, 1, 10), secret: "s3cr3t", discount: nil, **overrides
    )
  end

  def serialize(object = unit_type, **options) = UnitTypeResponse.serialize(object, version: "2025-09", **options)

  def test_serializes_an_object
    expected = {
      "id" => "ut_1", "name" => "Small", "stripe_product_id" => nil, "status" => "active",
      "selling_points" => ["Dry"], "created_at" => "2025-09-01T10:00:00Z", "secret" => nil, "object" => "unit_type"
    }

    assert_equal expected, serialize
  end

  def test_passes_context_to_blocks
    assert_equal "s3cr3t", serialize(context: {show_secret: true})["secret"]
  end

  def test_conditional_property
    assert_equal 10, serialize(unit_type(discount: 10))["discount"]
  end

  def test_serializes_hashes
    assert_equal serialize, serialize(unit_type.to_h)
  end

  def test_serializes_collections
    assert_equal %w[ut_1 ut_2], serialize([unit_type, unit_type(public_id: "ut_2")]).map { |item| item["id"] }
  end

  def test_resolves_the_closest_earlier_version
    assert_equal "ut_1", UnitTypeResponse.serialize(unit_type, version: "2026-01")["id"]
  end

  def test_raises_for_versions_before_the_first
    assert_raises(Versponse::VersionNotFoundError) { UnitTypeResponse.serialize(unit_type, version: "2024-01") }
  end

  def test_uses_the_current_version
    with_configuration(current_version: -> { "2025-09" }) do
      assert_equal "ut_1", UnitTypeResponse.serialize(unit_type)["id"]
    end
  end

  def test_requires_a_version
    assert_raises(ArgumentError) { UnitTypeResponse.serialize(unit_type) }
  end

  def test_does_not_freeze_the_callers_context
    context = {show_secret: true}
    serialize(context:)

    refute_predicate context, :frozen?
  end

  def test_to_json
    assert_equal "ut_1", JSON.parse(UnitTypeResponse.to_json(unit_type, version: "2025-09"))["id"]
  end

  def test_custom_json_generator
    with_configuration(json_generator: ->(hash) { "custom:#{hash["id"]}" }) do
      assert_equal "custom:ut_1", UnitTypeResponse.to_json(unit_type, version: "2025-09")
    end
  end

  def test_extraction_error_names_the_path
    error = assert_raises(Versponse::ExtractionError) { serialize(Struct.new(:public_id).new("ut_1")) }

    assert_match(%r{\ASerializeTest::UnitTypeResponse\[2025-09/default\]\.name: }, error.message)
  end

  def test_plans_are_cached
    assert_same UnitTypeResponse.plan(version: "2025-09"), UnitTypeResponse.plan(version: "2025-09")
  end

  def test_with_options
    klass = Class.new(Versponse::Base) do
      version "2025-09" do
        with_options type: :string, nullable: true do
          field :a
          field :b
        end
      end
    end

    assert_equal({"a" => nil, "b" => nil}, klass.serialize({a: nil, b: nil}, version: "2025-09"))
  end

  def test_explicit_options_override_with_options_and_unless
    klass = Class.new(Versponse::Base) do
      version "2025-09" do
        with_options type: :string, nullable: true do
          field :a, type: :integer, nullable: false
          field :b, unless: ->(object) { object[:hide_b] }
        end
      end
    end
    property = klass.resolve("2025-09").properties["a"]

    refute_predicate property, :nullable?
    assert_equal({"a" => 1}, klass.serialize({a: 1, b: "x", hide_b: true}, version: "2025-09"))
  end

  def test_requested_versions_are_canonicalized_before_caching
    assert_includes Versponse::Registry.version_names, UnitTypeResponse.send(:version_name, "2099-01-01-anything")
  end

  def test_root_and_meta
    result = UnitTypeResponse.serialize(unit_type, version: "2025-09", root: :unit_type, meta: {"request_id" => "r1"})

    assert_equal %w[unit_type meta], result.keys
    assert_equal({"request_id" => "r1"}, result["meta"])
  end

  def test_collection_under_root
    assert_equal ["ut_1"], UnitTypeResponse.serialize([unit_type], version: "2025-09", root: "unit_types")["unit_types"].map { |item| item["id"] }
  end

  def test_meta_requires_root
    error = assert_raises(ArgumentError) { serialize(meta: {}) }

    assert_equal "meta: requires root:", error.message
  end
end
