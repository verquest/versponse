# frozen_string_literal: true

require "test_helper"

class ContextOverrideTest < Minitest::Test
  def test_nil_builds_nothing
    assert_nil Versponse::ContextOverride.build(nil, key: "site")
  end

  def test_hash_merges_over_the_context_frozen
    override = Versponse::ContextOverride.build({embedded: true}, key: "site")
    child = override.call(Object.new, {embedded: false, other: 1}.freeze)

    assert_equal({embedded: true, other: 1}, child)
    assert_predicate child, :frozen?
  end

  def test_hash_over_an_empty_context_is_the_built_hash
    override = Versponse::ContextOverride.build({embedded: true}, key: "site")

    assert_same override.call(Object.new, {}.freeze), override.call(Object.new, {}.freeze)
  end

  def test_hash_is_deep_frozen_at_build
    options = {nested: {list: [1]}}
    child = Versponse::ContextOverride.build(options, key: "site").call(nil, {}.freeze)

    assert_predicate child[:nested][:list], :frozen?
    refute_predicate options, :frozen?
  end

  def test_callable_returns_the_child_context
    override = Versponse::ContextOverride.build(->(unit, context) { context.merge(currency: unit) }, key: "prices")

    assert_equal({a: 1, currency: "GBP"}, override.call("GBP", {a: 1}.freeze))
  end

  def test_one_argument_callable_gets_the_object
    override = Versponse::ContextOverride.build(->(unit) { {unit:} }, key: "prices")

    assert_equal({unit: "u1"}, override.call("u1", {a: 1}.freeze))
  end

  def test_callable_result_is_frozen
    assert_predicate Versponse::ContextOverride.build(->(_, _) { {a: 1} }, key: "k").call(nil, {}.freeze), :frozen?
  end

  def test_non_hash_result_raises_an_extraction_error
    error = assert_raises(Versponse::ExtractionError) do
      Versponse::ContextOverride.build(->(_, _) { 1 }, key: "site").call(nil, {}.freeze)
    end

    assert_equal "context: must return a Hash, got Integer", error.detail
    assert_empty error.keys
  end

  def test_other_values_raise_a_definition_error
    error = assert_raises(Versponse::DefinitionError) { Versponse::ContextOverride.build("x", key: "site") }

    assert_equal "site: context: must be a Hash or respond to call", error.message
  end

  def test_callable_arity_errors_name_the_property
    error = assert_raises(Versponse::DefinitionError) { Versponse::ContextOverride.build(->(_a, _b, _c) {}, key: "site") }

    assert_equal "site: context: callables take (object) or (object, context)", error.message
  end
end
