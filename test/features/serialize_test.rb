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
      "selling_points" => ["Dry"], "created_at" => "2025-09-01T10:00:00.000Z", "secret" => nil, "object" => "unit_type"
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
    assert_equal "ut_1", JSON.parse(UnitTypeResponse.serialize_json(unit_type, version: "2025-09"))["id"]
  end

  def test_custom_json_generator
    with_configuration(json_generator: ->(hash) { "custom:#{hash["id"]}" }) do
      assert_equal "custom:ut_1", UnitTypeResponse.serialize_json(unit_type, version: "2025-09")
    end
  end

  def test_extraction_error_names_the_path
    error = assert_raises(Versponse::ExtractionError) { serialize(Struct.new(:public_id).new("ut_1")) }

    assert_match(%r{\ASerializeTest::UnitTypeResponse\[2025-09/default\]\.name: }, error.message)
  end

  def test_plans_are_cached
    assert_same UnitTypeResponse.versponse.plan(version: "2025-09"), UnitTypeResponse.versponse.plan(version: "2025-09")
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
    property = klass.versponse.resolve("2025-09").properties["a"]

    refute_predicate property, :nullable?
    assert_equal({"a" => 1}, klass.serialize({a: 1, b: "x", hide_b: true}, version: "2025-09"))
  end

  def test_requested_versions_are_canonicalized_before_caching
    assert_equal UnitTypeResponse.versponse.version_name("2099-01-01-a"), UnitTypeResponse.versponse.version_name("2099-01-01-b")
  end

  # Internals live on klass.versponse, so a response class's own class methods can't break rendering
  def test_user_class_methods_do_not_clash_with_internals
    klass = Class.new(Versponse::Base) do
      def self.plan = "mine"
      def self.versions = "mine"
      def self.resolve(_version) = "mine"
      def self.checker = "mine"

      version("2025-09") { field :id, type: :string }
    end

    assert_equal({"id" => "1"}, klass.serialize({id: "1"}, version: "2025-09"))
  end

  def test_response_classes_keep_object_to_json
    assert_equal %({"k":"#{UnitTypeResponse.name}"}), JSON.generate({"k" => UnitTypeResponse})
    assert_equal UnitTypeResponse.name.to_json, UnitTypeResponse.to_json
  end

  def test_root_and_meta
    result = UnitTypeResponse.serialize(unit_type, version: "2025-09", root: :unit_type, meta: {"request_id" => "r1"})

    assert_equal %w[unit_type meta], result.keys
    assert_equal({"request_id" => "r1"}, result["meta"])
  end

  def test_top_level_collection_errors_name_the_item
    klass = Class.new(Versponse::Base) { version("2025-09") { field :n, type: :integer } }

    error = assert_raises(Versponse::ExtractionError) { klass.serialize([{n: 1}, {}], version: "2025-09") }

    assert_equal ["1", "n"], error.keys
  end

  def test_sets_render_as_collections
    klass = Class.new(Versponse::Base) do
      version("2025-09") { field(:n, type: :integer) && collection(:tags) { field :name, type: :string } }
    end

    assert_equal [{"n" => 1, "tags" => [{"name" => "a"}]}], klass.serialize(Set[{n: 1, tags: Set[{name: "a"}]}], version: "2025-09")
  end

  # A version before every declared one raises without leaving a cache entry behind
  def test_unknown_early_versions_are_not_cached
    klass = Class.new(Versponse::Base) { version("2025-09") { field :id, type: :string } }

    50.times { |index| assert_raises(Versponse::VersionNotFoundError) { klass.serialize({id: "1"}, version: "1999-#{index}") } }

    assert_empty klass.versponse.instance_variable_get(:@plans).instance_variable_get(:@store)
  end

  def test_non_collections_in_a_collection_raise
    klass = Class.new(Versponse::Base) { version("2025-09") { collection(:items) { field :id, type: :string } } }

    error = assert_raises(Versponse::ExtractionError) { klass.serialize({items: Struct.new(:id).new("x")}, version: "2025-09") }

    assert_match(/items: expected a collection, got /, error.message)
  end

  # The DSL's state and helpers live in klass.versponse.builder, so a class's own methods can't break them
  def test_user_helpers_do_not_clash_with_the_dsl
    klass = Class.new(Versponse::Base) do
      def self.nested = "mine"
      def self.add_property = "mine"
      def self.wrap = "mine"
      def self.default_options = "mine"

      version("2025-09") { object(:a) { field :b, type: :string } }
    end

    assert_equal({"r" => {"a" => {"b" => "x"}}}, klass.serialize({a: {b: "x"}}, version: "2025-09", root: :r))
  end

  def test_meta_keys_are_strings
    meta = {page: {next: "c2", sizes: [{per: 10}]}}
    result = UnitTypeResponse.serialize(unit_type, version: "2025-09", root: :unit_type, meta:)

    assert_equal({"page" => {"next" => "c2", "sizes" => [{"per" => 10}]}}, result["meta"])
  end

  def test_collection_under_root
    assert_equal ["ut_1"], UnitTypeResponse.serialize([unit_type], version: "2025-09", root: "unit_types")["unit_types"].map { |item| item["id"] }
  end

  def test_meta_requires_root
    error = assert_raises(ArgumentError) { serialize(meta: {}) }

    assert_equal "meta: requires root:", error.message
  end
end
