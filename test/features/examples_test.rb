# frozen_string_literal: true

require "test_helper"
require "json_schemer"

class ExamplesTest < Minitest::Test
  include ExampleObjects

  CLASSES = [
    Examples::MoneyResponse, Examples::SiteResponse, Examples::PriceResponse, Examples::UnitTypeResponse,
    Examples::OrderResponse, Examples::TenancyResponse, Examples::TaskResponse, Examples::ActivityFeedResponse, Examples::CategoryResponse,
    Examples::MetaResponse
  ].freeze

  def valid_schema?(schema)
    JSONSchemer.valid_schema?(schema, meta_schema: Versponse.configuration.json_schema_uri)
  end

  def test_component_schemas_are_valid_openapi
    %w[2025-09 2026-03].each do |version|
      Versponse.components(version:, classes: CLASSES).each do |name, schema|
        assert valid_schema?(schema), "#{name} (#{version}) is not a valid schema"
      end
    end
  end

  def test_validation_schemas_are_valid
    CLASSES.each do |klass|
      klass.versponse.resolve("2025-09").view_names.each do |view|
        assert valid_schema?(klass.to_validation_schema(version: "2025-09", view:)), "#{klass.name}/#{view}"
      end
    end
  end

  def test_wrapper_schema_is_valid
    schema = Examples::UnitTypeResponse.to_schema(version: "2025-09", root: "unit_types", meta: Examples::MetaResponse, collection: true)

    assert valid_schema?(schema)
  end

  def test_eager_load
    assert_equal CLASSES, Versponse.eager_load!(classes: CLASSES)
  end

  def test_unit_type
    expected = {
      "object" => "unit_type", "id" => "ut_1", "name" => "Small", "stripe_product_id" => "prod_1",
      "status" => "active", "selling_points" => ["Dry"], "created_at" => "2025-09-01T10:00:00Z",
      "site" => {"id" => "site_1", "name" => "Leeds", "address" => {"city" => "Leeds", "postcode" => nil}},
      "security_deposit" => nil,
      "prices" => [{"id" => "price_1", "amount" => {"amount" => 5000, "currency" => "GBP"}, "interval" => "month"}]
    }

    assert_equal expected, Examples::UnitTypeResponse.serialize(unit_type, version: "2025-09", expand: ["site"])
  end

  def test_unit_type_views_and_versions
    compact = Examples::UnitTypeResponse.serialize(unit_type, version: "2025-09", view: :embedded_without_prices)
    newer = Examples::UnitTypeResponse.serialize(unit_type, version: "2026-03", view: :embedded)

    assert_equal %w[object id name stripe_product_id status selling_points created_at security_deposit], compact.keys
    refute newer.key?("name")
    assert_equal "Small", newer["title"]
  end

  def test_order_and_tenancy_cycle
    expected = {"object" => "order", "id" => "o1", "tenancy" => {"object" => "tenancy", "id" => "t1"}}

    assert_equal expected, Examples::OrderResponse.serialize(order_with_tenancy, version: "2025-09")
  end

  def test_task_one_of
    task = Examples::Task.new(id: "task_1", title: "Call", resource: order_with_tenancy.tenancy)

    assert_equal({"object" => "tenancy", "id" => "t1"}, Examples::TaskResponse.serialize(task, version: "2025-09")["resource"])
  end

  def test_recursive_category
    tree = Examples::Category.new(name: "Root", children: [Examples::Category.new(name: "Leaf", children: [])])

    assert_equal "Leaf", Examples::CategoryResponse.serialize(tree, version: "2025-09")["children"].first["name"]
  end

  def test_activity_feed
    tenancy = order_with_tenancy.tenancy
    site = Examples::Site.new(public_id: "site_1", name: "Leeds", city: "Leeds", postcode: "LS1")
    feed = Examples::Feed.new(id: "feed_1", activity: [tenancy.order, tenancy], site:)
    expected = {
      "id" => "feed_1",
      "site_address" => {"city" => "Leeds", "postcode" => "LS1"},
      "activity" => [{"object" => "order", "id" => "o1"}, {"object" => "tenancy", "id" => "t1"}]
    }

    assert_equal expected, Examples::ActivityFeedResponse.serialize(feed, version: "2025-09")
  end

  def test_activity_feed_mapping
    discriminator = Examples::ActivityFeedResponse.to_schema(version: "2025-09")["properties"]["activity"]["items"]["discriminator"]
    expected = {"order" => "#/components/schemas/OrderResponseEmbedded", "tenancy" => "#/components/schemas/TenancyResponseEmbedded"}

    assert_equal expected, discriminator["mapping"]
  end

  def test_unit_type_site_is_collapsed_by_default
    assert_equal({"id" => "site_1"}, Examples::UnitTypeResponse.serialize(unit_type, version: "2025-09")["site"])
  end

  def test_expandable_paths
    assert_equal %w[site], Examples::UnitTypeResponse.expandable_paths(version: "2025-09")
    assert_equal %w[resource], Examples::TaskResponse.expandable_paths(version: "2025-09")
  end

  def test_task_resource_expanded
    task = Examples::Task.new(id: "task_1", title: "Call", resource: order_with_tenancy.tenancy)

    assert_equal({"object" => "tenancy", "id" => "t1"}, Examples::TaskResponse.serialize(task, version: "2025-09", expand: ["resource"])["resource"])
  end

  def test_public_api_document_is_valid_openapi
    %w[2025-09 2026-03].each do |version|
      assert_empty Examples::PublicApiDocument.validate(version:), "document #{version}"
    end
  end

  def test_public_api_document_components
    schemas = Examples::PublicApiDocument.build(version: "2025-09")["components"]["schemas"]

    assert_includes schemas.keys, "UnitTypeResponse"
    assert_includes schemas.keys, "SiteResponseCollapsed"
    assert_equal %w[unit_types meta], schemas["unit_type_list"]["required"]
    assert_includes schemas.keys, "Error"
  end
end
