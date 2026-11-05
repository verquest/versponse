# frozen_string_literal: true

require "test_helper"

class NestedTest < Minitest::Test
  UnitType = Struct.new(:width, :depth, :features, :address)
  Feature = Struct.new(:name, :highlight)

  class UnitTypeResponse < Versponse::Base
    version "2025-09" do
      object :dimensions, map: "." do
        field :width, type: :number
        field :depth, type: :number
      end

      object :address, nullable: true do
        field :city, type: :string
      end

      collection :features do
        field :name, type: :string
        field :highlighted, type: :boolean, map: "highlight"
      end
    end
  end

  def unit_type(**overrides)
    UnitType.new(width: 2.5, depth: 3, features: [Feature.new("Dry", true)], address: {city: "Prague"}, **overrides)
  end

  def serialize(object) = UnitTypeResponse.serialize(object, version: "2025-09")

  def test_renders_objects_and_collections
    expected = {
      "dimensions" => {"width" => 2.5, "depth" => 3},
      "address" => {"city" => "Prague"},
      "features" => [{"name" => "Dry", "highlighted" => true}]
    }

    assert_equal expected, serialize(unit_type)
  end

  def test_nil_source_renders_nil
    assert_nil serialize(unit_type(address: nil))["address"]
  end

  def test_schema
    properties = UnitTypeResponse.to_schema(version: "2025-09")["properties"]
    dimensions = {
      "type" => "object", "required" => %w[width depth],
      "properties" => {"width" => {"type" => "number"}, "depth" => {"type" => "number"}},
      "additionalProperties" => false
    }

    assert_equal dimensions, properties["dimensions"]
    assert_equal %w[object null], properties["address"]["type"]
    assert_equal "array", properties["features"]["type"]
    assert_equal %w[name highlighted], properties["features"]["items"]["required"]
  end

  def test_extraction_errors_include_nested_keys
    error = assert_raises(Versponse::ExtractionError) { serialize(unit_type(features: [Struct.new(:name).new("Dry")])) }

    assert_match(/\.features\.highlighted: /, error.message)
  end

  def test_definition_errors
    assert_raises(Versponse::DefinitionError) { Class.new(Versponse::Base) { version("2025-09") { object :a } } }
    assert_raises(Versponse::DefinitionError) { Class.new(Versponse::Base) { version("2025-09") { collection :a } } }
  end

  def test_reopening_an_embedded_class_refreshes_classes_that_embed_it
    child = Class.new(Versponse::Base) { version("2025-09") { field :name, type: :string } }
    holder = Class.new(Versponse::Base)
    holder.class_exec(child) { |item| version("2025-09") { collection :items, item: } }
    holder.serialize({items: [{name: "a"}]}, version: "2025-09")

    child.class_exec { version("2025-09", inherit: false) { field :title, type: :string } }

    assert_equal({"items" => [{"title" => "b"}]}, holder.serialize({items: [{title: "b"}]}, version: "2025-09"))
  end

  def test_collection_items_must_implement_the_protocol
    only_ref = Class.new { def self.to_ref(property: nil) = "#/x" }

    assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base).class_exec(only_ref) { |item| version("2025-09") { collection :a, item: } }
    end
  end
end
