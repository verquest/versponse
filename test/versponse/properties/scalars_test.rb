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

    assert_equal({"created_at" => "2025-09-01T10:00:00.000Z"}, render(field, Item.new(created_at: Time.utc(2025, 9, 1, 10))))
  end

  def test_field_map_and_block
    mapped = Versponse::Properties::Field.new(name: :name, type: :string, map: "title")
    computed = Versponse::Properties::Field.new(name: :name, type: :string, block: proc { |item| item.title.upcase })

    assert_equal({"name" => "Box"}, render(mapped, Item.new(title: "Box")))
    assert_equal({"name" => "BOX"}, render(computed, Item.new(title: "Box")))
  end

  def test_enum
    enum = Versponse::Properties::Enum.new(name: :status, type: :string, values: %w[active archived])
    nullable = Versponse::Properties::Enum.new(name: :status, type: :string, values: %w[active], nullable: true)

    assert_equal({"type" => "string", "enum" => %w[active archived]}, enum.schema(nil))
    assert_equal({"type" => %w[string null], "enum" => ["active", nil]}, nullable.schema(nil))
    with_configuration(json_schema_version: :openapi30) do
      assert_equal({"type" => "string", "enum" => %w[active], "nullable" => true}, nullable.schema(nil))
    end
  end

  def test_enum_keeps_schema_keywords
    enum = Versponse::Properties::Enum.new(name: :status, type: :string, values: %w[a], description: "State")

    assert_equal({"type" => "string", "enum" => %w[a], "description" => "State"}, enum.schema(nil))
  end

  def test_enum_requires_values
    assert_raises(Versponse::DefinitionError) { Versponse::Properties::Enum.new(name: :status, type: :string, values: []) }
  end

  def enum_schema(values, **options) = Versponse::Properties::Enum.new(name: :status, values:, **options).schema(nil)

  # Without type:, the type comes from the values, like verquest's query coercion
  def test_enum_infers_the_type_from_its_values
    assert_equal({"type" => "string", "enum" => %w[a b]}, enum_schema(%w[a b]))
    assert_equal({"type" => "integer", "enum" => [1, 2]}, enum_schema([1, 2]))
    assert_equal({"type" => "number", "enum" => [1, 2.5]}, enum_schema([1, 2.5]))
    assert_equal({"type" => "boolean", "enum" => [true, false]}, enum_schema([true, false]))
    assert_equal({"type" => %w[integer string], "enum" => [1, "a"]}, enum_schema([1, "a"]))
    assert_equal({"type" => %w[string null], "enum" => ["a", nil]}, enum_schema(["a", nil], nullable: true))
  end

  def test_enum_type_that_cannot_be_inferred
    error = assert_raises(Versponse::DefinitionError) { Versponse::Properties::Enum.new(name: :status, values: %i[a b]) }

    assert_equal "status: can't infer the enum type from :a, pass type: (Symbols render as Symbols, use Strings)", error.message
    assert_raises(Versponse::DefinitionError) { Versponse::Properties::Enum.new(name: :status, values: [nil], nullable: true) }
    assert_raises(Versponse::DefinitionError) { Versponse::Properties::Enum.new(name: :status, type: :text, values: %w[a]) }
  end

  def test_enum_values_must_match_the_type
    error = assert_raises(Versponse::DefinitionError) do
      Versponse::Properties::Enum.new(name: :level, type: :integer, values: [1, "2"])
    end

    assert_equal 'level: enum value "2" is not of type integer', error.message
  end

  def test_enum_rejects_values_of_another_type
    [[:string, [:a]], [:integer, [1.5]], [:boolean, [true, "false"]], [:object, [[]]], [:string, ["a", nil]],
      [%i[integer string], [1.5]]].each do |type, values|
      assert_raises(Versponse::DefinitionError) { Versponse::Properties::Enum.new(name: :a, type:, values:) }
    end
  end

  def test_enum_accepts_values_of_each_type
    {integer: [1, 2], number: [1, 1.5], boolean: [true, false], object: [{"a" => 1}]}.each do |type, values|
      enum = Versponse::Properties::Enum.new(name: :a, type:, values:)

      assert_equal({"type" => type.to_s, "enum" => values}, enum.schema(nil))
    end
  end

  def test_enum_type_union
    enum = Versponse::Properties::Enum.new(name: :period, type: %i[integer string], values: [0, "now"], nullable: true)

    assert_equal({"type" => %w[integer string null], "enum" => [0, "now", nil]}, enum.schema(nil))
    with_configuration(json_schema_version: :openapi30) do
      expected = {"anyOf" => [{"type" => "integer"}, {"type" => "string"}], "enum" => [0, "now"], "nullable" => true}

      assert_equal(expected, enum.schema(nil))
    end
  end

  def test_enum_takes_only_the_base_type_of_a_custom_type
    with_configuration(custom_field_types: {site_id: {type: "string", schema_options: {pattern: "^site_"}}}) do
      enum = Versponse::Properties::Enum.new(name: :site, type: :site_id, values: %w[site_1])

      assert_equal({"type" => "string", "enum" => %w[site_1]}, enum.schema(nil))
      assert_raises(Versponse::DefinitionError) { Versponse::Properties::Enum.new(name: :site, type: :site_id, values: [1]) }
    end
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
    Versponse::Properties::Enum.new(name: :flag, type: :boolean, values:)

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

  # The same value goes into every response, so a nested change must not leak into later ones
  def test_const_value_is_deeply_frozen
    value = {"a" => [+"x"]}
    rendered = render(Versponse::Properties::Const.new(name: :meta, value:), Item.new)["meta"]

    refute_predicate value["a"], :frozen?
    assert_predicate rendered["a"], :frozen?
    assert_predicate rendered["a"].first, :frozen?
  end

  def test_nullable_enum_does_not_duplicate_nil
    enum = Versponse::Properties::Enum.new(name: :status, type: :string, values: ["a", nil], nullable: true)

    assert_equal({"type" => %w[string null], "enum" => ["a", nil]}, enum.schema(nil))
  end
end
