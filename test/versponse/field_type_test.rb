# frozen_string_literal: true

require "test_helper"

class Versponse::FieldTypeTest < Minitest::Test
  include ConfigurationTestHelper

  def normalize(definition, name: :site_id) = Versponse::FieldType.normalize(name, definition)

  def test_normalize
    normalized = normalize({type: :string, schema_options: {pattern: /^site_/, max_length: 20}, required: true})

    assert_equal({"type" => "string", "schema_options" => {"pattern" => "^site_", "maxLength" => 20}}, normalized)
    assert_predicate normalized["schema_options"], :frozen?
  end

  def test_normalize_keeps_property_names_and_accepts_string_keys
    normalized = normalize({"type" => "object", "schema_options" => {properties: {notice_period: {type: "integer"}}, additionalProperties: false}})

    assert_equal({"properties" => {"notice_period" => {"type" => "integer"}}, "additionalProperties" => false}, normalized["schema_options"])
  end

  def test_normalize_without_schema_options
    assert_equal({"type" => "string", "schema_options" => {}}, normalize({type: "string"}))
  end

  def test_normalize_errors
    assert_raises(ArgumentError) { normalize({type: :string}, name: :string) }
    assert_raises(ArgumentError) { normalize("string") }
    assert_raises(ArgumentError) { normalize({schema_options: {}}) }
    assert_raises(ArgumentError) { normalize({type: :date}) }
    assert_raises(ArgumentError) { normalize({type: :string, format: "email"}) }
  end

  def test_resolve_built_in
    assert_equal ["integer", {}], Versponse::FieldType.resolve(:integer, "count")
  end

  def test_resolve_custom
    with_configuration(custom_field_types: {site_id: {type: :string, schema_options: {pattern: "^site_"}}}) do
      assert_equal ["string", {"pattern" => "^site_"}], Versponse::FieldType.resolve(:site_id, "id")
    end
  end

  def test_resolve_unknown_names_every_type
    with_configuration(custom_field_types: {site_id: {type: :string}}) do
      error = assert_raises(Versponse::DefinitionError) { Versponse::FieldType.resolve(:unit_id, "id") }

      assert_equal "id: type must be one of string, number, integer, boolean, object, site_id", error.message
    end
  end
end
