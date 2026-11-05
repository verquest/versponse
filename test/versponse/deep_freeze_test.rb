# frozen_string_literal: true

require "test_helper"

class Versponse::DeepFreezeTest < Minitest::Test
  def test_returns_a_frozen_copy_without_freezing_the_original
    original = {"a" => [{"b" => +"c"}]}
    frozen = Versponse::DeepFreeze.call(original)

    assert_equal original, frozen
    assert_predicate frozen["a"].first["b"], :frozen?
    refute_predicate original["a"].first, :frozen?
  end
end
