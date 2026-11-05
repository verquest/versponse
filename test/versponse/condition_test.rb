# frozen_string_literal: true

require "test_helper"

class Versponse::ConditionTest < Minitest::Test
  def test_build_returns_nil_without_callables
    assert_nil Versponse::Condition.build(nil, nil)
  end

  def test_if
    condition = Versponse::Condition.build(->(object, _context) { object > 1 }, nil)

    assert condition.call(2, {})
    refute condition.call(1, {})
  end

  def test_unless_with_one_argument_lambda
    condition = Versponse::Condition.build(nil, ->(object) { object > 1 })

    assert condition.call(1, {})
    refute condition.call(2, {})
  end

  def test_if_and_unless_together
    condition = Versponse::Condition.build(->(object, _context) { object > 1 }, ->(_object, context) { context[:hide] })

    assert condition.call(2, {})
    refute condition.call(2, {hide: true})
  end
end
