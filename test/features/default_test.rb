# frozen_string_literal: true

require "test_helper"

class DefaultTest < Minitest::Test
  include ConfigurationTestHelper

  Item = Struct.new(:id, :name, :status, :tags, :seen_at)

  class ItemResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      field :name, type: :string, default: "unnamed"
      enum :status, values: %w[active archived], default: "active"
      array :tags, type: :string, default: []
      field :seen_at, type: :string, format: "date-time", default: ->(_item, context) { context[:now] }
    end
  end

  class ReuseResponse < Versponse::Base
    version "2025-09" do
      reference :label, from: ItemResponse, property: :name
    end
  end

  class ItemDocument < Versponse::OpenAPI::Document
    info "title" => "Items"
    responses [ItemResponse]
  end

  NOW = Time.utc(2026, 11, 7, 12)

  def serialize(item) = ItemResponse.serialize(item, version: "2025-09", context: {now: NOW})

  # date-time values render with milliseconds by default
  def test_defaults_replace_nil_only
    assert_equal({"id" => "i1", "name" => "unnamed", "status" => "active", "tags" => [], "seen_at" => "2026-11-07T12:00:00.000Z"}, serialize(Item.new("i1")))
    item = Item.new("i1", "Box", "archived", ["a"], Time.utc(2026, 1, 1))

    assert_equal({"id" => "i1", "name" => "Box", "status" => "archived", "tags" => ["a"], "seen_at" => "2026-01-01T00:00:00.000Z"}, serialize(item))
  end

  def test_static_defaults_are_in_the_schema
    properties = ItemResponse.to_schema(version: "2025-09")["properties"]

    assert_equal "unnamed", properties["name"]["default"]
    assert_equal "active", properties["status"]["default"]
    assert_equal [], properties["tags"]["default"]
    refute properties["seen_at"].key?("default")
  end

  def test_static_defaults_are_in_the_openapi_document
    properties = ItemDocument.build(version: "2025-09")["components"]["schemas"].fetch("ItemResponse")["properties"]

    assert_equal "unnamed", properties["name"]["default"]
    refute properties["seen_at"].key?("default")
  end

  def test_invalid_static_default_raises
    error = assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) { version("2025-09") { field :count, type: :integer, default: "x" } }
    end

    assert_equal "count: default: \"x\" doesn't match the property's schema", error.message
    assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) { version("2025-09") { enum :status, values: %w[a b], default: "c" } }
    end
  end

  def test_associations_and_const_reject_default
    error = assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) { version("2025-09") { reference :item, from: ItemResponse, default: {} } }
    end

    assert_equal "item: default: only works on field, enum and array", error.message
    assert_raises(Versponse::DefinitionError) { Class.new(Versponse::Base) { version("2025-09") { const :object, value: "item", default: "item" } } }
  end

  def test_with_options_default_skips_associations
    klass = Class.new(Versponse::Base) do
      version("2025-09") do
        with_options default: "x" do
          field :name, type: :string
          reference :item, from: ItemResponse, nullable: true
        end
      end
    end

    assert_equal({"name" => "x", "item" => nil}, klass.serialize({name: nil, item: nil}, version: "2025-09"))
  end

  def test_reference_property_carries_the_default_over
    assert_equal({"label" => "unnamed"}, ReuseResponse.serialize(Item.new("i1"), version: "2025-09"))
  end

  def test_rendered_arrays_are_new_arrays
    klass = Class.new(Versponse::Base) { version("2025-09") { array :tags, type: :string } }
    tags = ["a"]

    klass.serialize({tags:}, version: "2025-09")["tags"] << "b"

    assert_equal ["a"], tags
  end

  # A Hash or Array default: or const is a copy, so changing the output doesn't touch later renders
  def test_static_hash_and_array_values_are_copies
    klass = Class.new(Versponse::Base) do
      version("2025-09") do
        array :flags, type: :string, default: ["new"]
        field :settings, type: :object, default: {"theme" => "dark"}
        const :links, value: {"self" => "/x"}
      end
    end
    output = klass.serialize({flags: nil, settings: nil}, version: "2025-09")

    output["flags"] << "seen"
    output["settings"]["theme"] = "light"
    output["links"]["self"] = "/y"

    assert_equal({"flags" => ["new"], "settings" => {"theme" => "dark"}, "links" => {"self" => "/x"}}, klass.serialize({flags: nil, settings: nil}, version: "2025-09"))
  end
end
