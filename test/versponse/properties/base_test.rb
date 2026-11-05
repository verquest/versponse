# frozen_string_literal: true

require "test_helper"

class Versponse::Properties::BaseTest < Minitest::Test
  include ConfigurationTestHelper

  class TestProperty < Versponse::Properties::Base
    def schema(context) = nullable_type({"type" => "string"}.merge(schema_options), context)
  end

  def test_name_and_key
    property = TestProperty.new(name: :full_name)

    assert_equal :full_name, property.name
    assert_equal "full_name", property.key
    assert_predicate property.key, :frozen?
  end

  def test_schema_options_are_camelized
    property = TestProperty.new(name: :a, min_length: 1, description: "A")

    assert_equal({"type" => "string", "minLength" => 1, "description" => "A"}, property.schema(nil))
  end

  def test_nullable_type
    assert_equal({"type" => %w[string null]}, TestProperty.new(name: :a, nullable: true).schema(nil))

    with_configuration(json_schema_version: :openapi30) do
      assert_equal({"type" => "string", "nullable" => true}, TestProperty.new(name: :a, nullable: true).schema(nil))
    end
  end

  def test_nullable_type_uses_the_3_1_form_for_validation
    validation = Struct.new(:validation?).new(true)

    with_configuration(json_schema_version: :openapi30) do
      assert_equal({"type" => %w[string null]}, TestProperty.new(name: :a, nullable: true).schema(validation))
    end
  end

  def test_nullable_ref_depends_on_the_context
    property = TestProperty.new(name: :a, nullable: true)
    ref = {"$ref" => "#/x"}

    with_configuration(json_schema_version: :openapi30) do
      assert_equal({"allOf" => [ref], "nullable" => true}, property.send(:nullable_ref, ref, Struct.new(:validation?).new(false)))
      assert_equal({"anyOf" => [ref, {"type" => "null"}]}, property.send(:nullable_ref, ref, Struct.new(:validation?).new(true)))
    end
  end

  def test_condition
    assert_predicate TestProperty.new(name: :a, if: ->(_object, _context) { true }), :conditional?
    refute_predicate TestProperty.new(name: :b), :conditional?
  end

  def test_map_is_stored_as_a_string
    assert_equal "billing_id", TestProperty.new(name: :a, map: :billing_id).map
  end

  def test_block_and_map_conflict
    assert_raises(Versponse::DefinitionError) { TestProperty.new(name: :a, map: "b", block: proc {}) }
  end

  def test_required_is_rejected
    error = assert_raises(Versponse::DefinitionError) { TestProperty.new(name: :a, required: true) }

    assert_match(/required is computed automatically/, error.message)
  end
end
