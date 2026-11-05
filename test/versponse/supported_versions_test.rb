# frozen_string_literal: true

require "test_helper"

class Versponse::SupportedVersionsTest < Minitest::Test
  include ConfigurationTestHelper

  # Orders "v9" before "v10", unlike string comparison
  NUMERIC = lambda do |requested, versions|
    number = ->(name) { name.delete_prefix("v").to_i }
    versions.select { |name| number.call(name) <= number.call(requested) }.max_by(&number)
  end

  def range(min: nil, max: nil) = Versponse::SupportedVersions.new(min:, max:)

  def test_covers_versions_between_min_and_max
    supported = range(min: "2025-09", max: "2026-03")

    assert supported.covers?("2025-09")
    assert supported.covers?("2026-03")
    refute supported.covers?("2025-06")
    refute supported.covers?("preview")
  end

  def test_bounds_are_optional
    assert range(min: "2025-09").covers?("preview")
    assert range(max: "2025-09").covers?("2025-06")
    refute range(max: "2025-09").covers?("preview")
  end

  def test_min_after_max_raises
    error = assert_raises(Versponse::DefinitionError) { range(min: "preview", max: "2025-09") }

    assert_equal "supported_versions min: preview is after max: 2025-09", error.message
  end

  def test_check_raises_when_max_is_before_every_declared_version
    error = assert_raises(Versponse::DefinitionError) { range(max: "2025-06").check!(%w[2025-09 preview], "OverlockResponse") }

    assert_equal "OverlockResponse: supported_versions max: 2025-06 is before every declared version (2025-09, preview)", error.message
    assert_nil range(min: "2025-06", max: "2025-09").check!(%w[2025-09 preview], "OverlockResponse")
    assert_nil range(max: "2025-06").check!([], "OverlockResponse")
  end

  def test_check_allows_min_after_every_declared_version
    assert_nil range(min: "preview").check!(%w[2025-09], "OverlockResponse")
  end

  def test_order_follows_the_configured_resolver
    assert_raises(Versponse::DefinitionError) { range(min: "v9", max: "v10") }

    with_configuration(version_resolver: NUMERIC) do
      supported = range(min: "v9", max: "v10")

      assert supported.covers?("v10")
      refute supported.covers?("v11")
    end
  end

  def test_to_s_and_frozen
    assert_equal "min: 2025-09, max: none", range(min: "2025-09").to_s
    assert_equal "min: first declared, max: 2026-03", range(max: "2026-03").to_s
    assert_predicate range, :frozen?
  end
end
