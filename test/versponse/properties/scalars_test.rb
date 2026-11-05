# frozen_string_literal: true

require "test_helper"

class Versponse::Properties::ScalarsTest < Minitest::Test
  include ConfigurationTestHelper

  Item = Struct.new(:title, :status, :tags, :created_at)

  def render(property, object)
    Versponse::Plan.new(label: "Item", steps: [property.step(version: "2025-09")]).call(object, {})
  end

  def test_field_schema
    field = Versponse::Properties::Field.new(name: :title, type: :string, max_length: 50)

    assert_equal({"type" => "string", "maxLength" => 50}, field.schema(nil))
  end

  def test_field_requires_a_known_type
    assert_raises(Versponse::DefinitionError) { Versponse::Properties::Field.new(name: :title, type: :text) }
    assert_raises(Versponse::DefinitionError) { Versponse::Properties::Field.new(name: :title, type: nil) }
  end

  def test_field_uses_the_formatter_of_its_format
    field = Versponse::Properties::Field.new(name: :created_at, type: :string, format: "date-time")

    assert_equal({"created_at" => "2025-09-01T10:00:00Z"}, render(field, Item.new(created_at: Time.utc(2025, 9, 1, 10))))
  end

  def test_field_map_and_block
    mapped = Versponse::Properties::Field.new(name: :name, type: :string, map: "title")
    computed = Versponse::Properties::Field.new(name: :name, type: :string, block: proc { |item| item.title.upcase })

    assert_equal({"name" => "Box"}, render(mapped, Item.new(title: "Box")))
    assert_equal({"name" => "BOX"}, render(computed, Item.new(title: "Box")))
  end

  def test_enum
    enum = Versponse::Properties::Enum.new(name: :status, values: %w[active archived])
    nullable = Versponse::Properties::Enum.new(name: :status, values: %w[active], nullable: true)

    assert_equal({"enum" => %w[active archived]}, enum.schema(nil))
    assert_equal({"enum" => ["active", nil]}, nullable.schema(nil))
    with_configuration(json_schema_version: :openapi30) do
      assert_equal({"enum" => %w[active], "nullable" => true}, nullable.schema(nil))
    end
  end

  def test_enum_requires_values
    assert_raises(Versponse::DefinitionError) { Versponse::Properties::Enum.new(name: :status, values: []) }
  end

  def test_const
    const = Versponse::Properties::Const.new(name: :object, value: "item")

    assert_equal({"const" => "item"}, const.schema(nil))
    assert_equal({"object" => "item"}, render(const, Item.new))
    with_configuration(json_schema_version: :openapi30) do
      assert_equal({"enum" => ["item"]}, const.schema(nil))
    end
  end

  def test_array
    array = Versponse::Properties::Array.new(name: :tags, type: :string, item_schema_options: {min_length: 1})

    assert_equal({"type" => "array", "items" => {"type" => "string", "minLength" => 1}}, array.schema(nil))
    assert_equal({"tags" => %w[a b]}, render(array, Item.new(tags: %w[a b])))
  end

  def test_nullable_array
    array = Versponse::Properties::Array.new(name: :tags, type: :string, nullable: true)

    assert_equal %w[array null], array.schema(nil)["type"]
  end

  def test_array_items_use_the_formatter_of_their_format
    array = Versponse::Properties::Array.new(name: :tags, type: :string, item_schema_options: {format: "date"})

    assert_equal({"tags" => ["2025-09-01"]}, render(array, Item.new(tags: [Date.new(2025, 9, 1)])))
  end

  def test_enum_accepts_falsy_values_and_does_not_freeze_the_callers_array
    values = [false, true]
    Versponse::Properties::Enum.new(name: :flag, values:)

    refute_predicate values, :frozen?
  end

  def test_object_field_is_a_free_form_map
    field = Versponse::Properties::Field.new(name: :metadata, type: :object, additional_properties: {type: "string"})

    assert_equal({"type" => "object", "additionalProperties" => {"type" => "string"}}, field.schema(nil))
    assert_equal({"metadata" => {"a" => "b"}}, render(field, Struct.new(:metadata).new({"a" => "b"})))
  end

  def test_const_rejects_block_map_and_nullable
    assert_raises(Versponse::DefinitionError) { Versponse::Properties::Const.new(name: :a, value: 1, block: proc { 2 }) }
    assert_raises(Versponse::DefinitionError) { Versponse::Properties::Const.new(name: :a, value: 1, map: "b") }
    assert_raises(Versponse::DefinitionError) { Versponse::Properties::Const.new(name: :a, value: 1, nullable: true) }
  end

  def test_const_value_is_frozen
    value = +"item"
    Versponse::Properties::Const.new(name: :object, value:)

    refute_predicate value, :frozen?
    assert_predicate render(Versponse::Properties::Const.new(name: :object, value:), Item.new)["object"], :frozen?
  end

  def test_nullable_enum_does_not_duplicate_nil
    enum = Versponse::Properties::Enum.new(name: :status, values: ["a", nil], nullable: true)

    assert_equal({"enum" => ["a", nil]}, enum.schema(nil))
  end
end
