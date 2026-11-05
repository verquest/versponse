# frozen_string_literal: true

require "test_helper"

class Versponse::VersionResolverTest < Minitest::Test
  VERSIONS = %w[2025-01 2025-06 2026-01].freeze

  def resolve(requested, versions = VERSIONS)
    Versponse::VersionResolver.call(requested, versions)
  end

  def test_exact_match
    assert_equal "2025-06", resolve("2025-06")
  end

  def test_between_versions_returns_the_earlier_one
    assert_equal "2025-01", resolve("2025-04")
  end

  def test_after_the_latest_returns_the_latest
    assert_equal "2026-01", resolve("2027-01")
  end

  def test_before_the_earliest_returns_nil
    assert_nil resolve("2024-12")
  end

  def test_no_versions_returns_nil
    assert_nil resolve("2025-01", [])
  end
end
