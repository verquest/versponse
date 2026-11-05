# frozen_string_literal: true

require "test_helper"

class Versponse::PlanTest < Minitest::Test
  Person = Struct.new(:name, :born_on)

  def value_step(key, condition: nil, formatter: nil)
    Versponse::Steps::Value.new(key:, extractor: Versponse::Extractors::Key.new(key), condition:, formatter:)
  end

  def plan(*steps, label: "Person")
    Versponse::Plan.new(label:, steps:)
  end

  def test_builds_a_hash_with_string_keys
    assert_equal({"name" => "Ann"}, plan(value_step("name")).call(Person.new("Ann"), {}))
  end

  def test_reads_hashes
    assert_equal({"name" => "Ann"}, plan(value_step("name")).call({name: "Ann"}, {}))
  end

  def test_skips_steps_whose_condition_fails
    condition = Versponse::Condition.build(->(person) { person.name == "Bob" }, nil)

    assert_empty plan(value_step("name", condition:)).call(Person.new("Ann"), {})
  end

  def test_formats_non_nil_values
    formatted = plan(value_step("born_on", formatter: Versponse::Formatters::DATE))

    assert_equal({"born_on" => "2000-01-02"}, formatted.call(Person.new("Ann", Date.new(2000, 1, 2)), {}))
    assert_equal({"born_on" => nil}, formatted.call(Person.new("Ann", nil), {}))
  end

  def test_const_step
    const = Versponse::Steps::Const.new(key: "object", value: "person", condition: nil)

    assert_equal({"object" => "person"}, plan(const).call(Person.new, {}))
  end

  def test_wraps_errors_in_extraction_error
    error = assert_raises(Versponse::ExtractionError) { plan(value_step("missing"), label: "Person[v1/default]").call(Person.new, {}) }

    assert_equal ["missing"], error.keys
    assert_match(%r{\APerson\[v1/default\]\.missing: undefined method}, error.message)
  end

  def test_prefixes_nested_extraction_errors
    failing = Object.new
    def failing.key = "person"

    def failing.call(*)
      raise Versponse::ExtractionError.new(label: "Inner", keys: ["missing"], detail: "boom")
    end

    error = assert_raises(Versponse::ExtractionError) { plan(failing, label: "Outer").call({}, {}) }

    assert_equal "Outer.person.missing: boom", error.message
  end

  def test_wraps_key_errors_from_hash_sources
    error = assert_raises(Versponse::ExtractionError) do
      plan(value_step("a")).call(Hash.new { |_hash, key| raise KeyError, "no #{key}" }, {})
    end

    assert_equal ["a"], error.keys
  end

  def test_does_not_freeze_the_callers_steps
    steps = [value_step("name")]
    Versponse::Plan.new(label: "Person", steps:)

    refute_predicate steps, :frozen?
  end

  def test_plan_is_frozen
    assert_predicate plan(value_step("name")), :frozen?
  end
end
