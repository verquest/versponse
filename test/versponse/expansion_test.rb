# frozen_string_literal: true

require "test_helper"

class Versponse::ExpansionTest < Minitest::Test
  def build(paths) = Versponse::Expansion.build(paths)

  def test_none_expands_nothing
    refute Versponse::Expansion::NONE.expand?("site")
    assert_same Versponse::Expansion::NONE, Versponse::Expansion::NONE.child("site")
  end

  def test_build_from_dotted_paths
    expansion = build(%w[site deal.stage])

    assert expansion.expand?("site")
    assert expansion.expand?("deal")
    refute expansion.expand?("contact")
    assert expansion.child("deal").expand?("stage")
    refute expansion.child("site").expand?("address")
  end

  def test_all_expands_everything_at_every_depth
    all = Versponse::Expansion::ALL

    assert all.expand?("anything")
    assert_same all, all.child("anything")
  end

  def test_wildcard_empty_and_symbols
    assert_same Versponse::Expansion::ALL, build(["*", "site"])
    assert_same Versponse::Expansion::NONE, build([])
    assert build([:site]).expand?("site")
  end

  def test_is_frozen
    assert_predicate build(%w[site]), :frozen?
  end
end
