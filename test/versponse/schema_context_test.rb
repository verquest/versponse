# frozen_string_literal: true

require "test_helper"

class Versponse::SchemaContextTest < Minitest::Test
  def context(validation: true) = Versponse::SchemaContext.new(version: "2025-09", validation:)

  def recursive(context, identity = :a) = context.inline(identity, "A") { {"properties" => {"child" => context.inline(identity, "A") { flunk }}} }

  def test_inline_returns_the_block_result
    assert_equal({"type" => "object"}, context.inline(:a, "A") { {"type" => "object"} })
  end

  def test_different_identities_with_the_same_name_are_not_recursion
    shared = context
    schema = shared.inline(:outer, "A") { {"child" => shared.inline(:inner, "A") { {"type" => "object"} }} }

    assert_equal({"child" => {"type" => "object"}}, schema)
  end

  def test_anchor_names_stay_unique
    shared = context
    recursive(shared, :first)

    assert_equal "A2", recursive(shared, :second)["$anchor"]
  end

  def test_anonymous_components_get_a_named_anchor
    shared = context
    schema = shared.inline(:anon, "") { {"child" => shared.inline(:anon, "") { flunk }} }

    assert_equal "Anonymous", schema["$anchor"]
  end

  def test_recursion_becomes_an_anchor_reference
    schema = recursive(context)

    assert_equal({"$ref" => "#A"}, schema["properties"]["child"])
    assert_equal "A", schema["$anchor"]
  end

  def test_later_inlines_of_an_anchored_component_reference_it
    shared = context
    recursive(shared)

    assert_equal({"$ref" => "#A"}, shared.inline(:a, "A") { flunk })
  end

  def test_validation_flag
    refute_predicate context(validation: false), :validation?
  end
end
