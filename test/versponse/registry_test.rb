# frozen_string_literal: true

require "test_helper"

class Versponse::RegistryTest < Minitest::Test
  def teardown
    self.class.send(:remove_const, :ReloadedResponse) if self.class.const_defined?(:ReloadedResponse, false)
  end

  def test_reloading_a_class_replaces_the_stale_one
    2.times do
      teardown
      self.class.class_eval "class ReloadedResponse < Versponse::Base; end", __FILE__, __LINE__
    end

    assert_equal [ReloadedResponse], Versponse::Registry.all.select { |klass| klass.name == ReloadedResponse.name }
  end

  def test_anonymous_classes_are_kept
    first = Class.new(Versponse::Base)
    second = Class.new(Versponse::Base)

    assert_includes Versponse::Registry.all, first
    assert_includes Versponse::Registry.all, second
  end

  # Canonical names are memoized per requested String, and recomputed once registered names change
  def test_canonical_results_are_cached_until_names_change
    cache = -> { Versponse::Registry.instance_variable_get(:@canonical) }
    Versponse::Registry.canonical("2099-12-31-cached")

    assert cache.call["2099-12-31-cached"]
    Versponse::Registry.add_version_name("2099-12-31-cached")

    assert_nil cache.call["2099-12-31-cached"]
    assert_equal "2099-12-31-cached", Versponse::Registry.canonical("2099-12-31-cached")
  end

  # A request before every registered name maps to itself and isn't stored, so it can't fill the cache
  def test_requests_before_every_name_are_not_cached
    Versponse::Registry.canonical("0000-early")

    assert_nil Versponse::Registry.instance_variable_get(:@canonical)["0000-early"]
  end

  # Undeclared names resolve to the same declared version, so caches keyed by it don't grow with client strings
  def test_undeclared_names_share_a_canonical_version
    assert_equal Versponse::Registry.canonical("2099-01-01-a"), Versponse::Registry.canonical("2099-01-01-b")
  end
end
