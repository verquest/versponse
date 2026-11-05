# frozen_string_literal: true

require "test_helper"

class Versponse::VariantDispatcherTest < Minitest::Test
  FakePlan = Struct.new(:tag) do
    def call(value, _context) = {tag => value}
  end

  def dispatcher(nullable: false)
    Versponse::VariantDispatcher.new(
      [[[Integer].freeze, FakePlan.new("int")], [[String, Symbol].freeze, FakePlan.new("text")]],
      nullable:
    )
  end

  def test_uses_the_first_matching_variant
    assert_equal({"int" => 1}, dispatcher.call(1, {}))
    assert_equal({"text" => :a}, dispatcher.call(:a, {}))
  end

  def test_raises_key_error_without_a_match
    error = assert_raises(KeyError) { dispatcher.call(1.5, {}) }

    assert_equal "no one_of variant matches Float", error.message
  end

  def test_nil_is_rendered_only_when_nullable
    assert_nil dispatcher(nullable: true).call(nil, {})
    assert_raises(KeyError) { dispatcher.call(nil, {}) }
  end

  def test_is_frozen
    assert_predicate dispatcher, :frozen?
  end
end
