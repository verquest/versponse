# frozen_string_literal: true

require "test_helper"

class Versponse::DeepCopyTest < Minitest::Test
  def test_copies_are_unfrozen_all_the_way_down
    original = Versponse::DeepFreeze.call({"a" => [{"b" => "c"}], "d" => 1})
    copy = Versponse::DeepCopy.call(original)

    assert_equal original, copy
    refute_predicate copy, :frozen?
    refute_predicate copy["a"], :frozen?
    refute_predicate copy["a"][0], :frozen?
    refute_predicate copy["a"][0]["b"], :frozen?
  end

  def test_containers
    assert Versponse::DeepCopy.container?({})
    assert Versponse::DeepCopy.container?([])
    refute Versponse::DeepCopy.container?("a")
  end
end
