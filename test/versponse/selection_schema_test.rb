# frozen_string_literal: true

require "test_helper"
require "json_schemer"

class SelectionSchemaTest < Minitest::Test
  OBJECT = {
    "type" => "object",
    "properties" => {
      "id" => {"type" => "string"},
      "status" => {"type" => "string"},
      "site" => {"anyOf" => [
        {"type" => "object", "properties" => {"id" => {"type" => "string"}, "name" => {"type" => "string"}}, "required" => %w[id name]},
        {"type" => "null"}
      ]},
      "lines" => {"type" => "array", "items" => {"type" => "object", "properties" => {"note" => {"type" => "string"}, "total" => {"type" => "integer"}}, "required" => %w[note total]}},
      "resource" => {"oneOf" => [
        {"type" => "object", "properties" => {"text" => {"type" => "string"}, "author" => {"type" => "string"}}, "required" => %w[text author], "additionalProperties" => false},
        {"type" => "object", "properties" => {"text" => {"type" => "string"}, "duration" => {"type" => "integer"}}, "required" => %w[text duration], "additionalProperties" => false}
      ]}
    },
    "required" => %w[id status site lines resource]
  }.freeze

  # A recursive class: inlined once with an anchor, referenced below
  CATEGORY = {
    "$anchor" => "Category",
    "type" => "object",
    "properties" => {"name" => {"type" => "string"}, "children" => {"type" => "array", "items" => {"$ref" => "#Category"}}},
    "required" => %w[name children],
    "additionalProperties" => false
  }.freeze

  def prune(*paths, schema: OBJECT) = Versponse::SelectionSchema.call(schema, Versponse::Selection.build(paths))

  def valid?(schema, data) = JSONSchemer.schema(schema).valid?(data)

  def test_all_returns_the_schema
    assert_same OBJECT, Versponse::SelectionSchema.call(OBJECT, Versponse::Selection::ALL)
  end

  def test_required_keeps_selected_keys
    assert_equal %w[status], prune("status")["required"]
    assert_equal OBJECT["properties"].keys, prune("status")["properties"].keys
  end

  def test_missing_selected_key_still_fails
    refute valid?(prune("status"), {"id" => "1"})
    assert valid?(prune("status"), {"id" => "1", "status" => "open"})
  end

  def test_prunes_through_any_of_and_items
    schema = prune("site.name", "lines.note")

    assert_equal %w[name], schema["properties"]["site"]["anyOf"][0]["required"]
    assert_equal %w[note], schema["properties"]["lines"]["items"]["required"]
  end

  def test_whole_association_keeps_its_required
    assert_equal %w[id name], prune("site")["properties"]["site"]["anyOf"][0]["required"]
  end

  def test_one_of_becomes_any_of
    resource = prune("resource.text")["properties"]["resource"]

    refute resource.key?("oneOf")
    assert valid?(prune("resource.text"), {"resource" => {"text" => "t"}})
  end

  def test_recursive_refs_are_pruned_and_the_rest_stays_full
    pruned = prune("children.name", schema: CATEGORY)

    assert valid?(pruned, {"children" => [{"name" => "a"}]})
    refute valid?(pruned, {"children" => [{"name" => 1}]})
    whole = prune("children", schema: CATEGORY)

    refute valid?(whole, {"children" => [{"name" => "a"}]})
    assert valid?(whole, {"children" => [{"name" => "a", "children" => []}]})
  end
end
