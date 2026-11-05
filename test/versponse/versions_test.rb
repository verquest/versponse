# frozen_string_literal: true

require "test_helper"

class Versponse::VersionsTest < Minitest::Test
  include ConfigurationTestHelper

  def setup
    @versions = Versponse::Versions.new
    %w[2025-06 2025-01].each { |name| @versions.add(Versponse::Version.new(name:, owner: "X").tap(&:finalize!)) }
  end

  def test_sorted_names
    assert_equal %w[2025-01 2025-06], @versions.sorted_names
  end

  def test_resolve_closest_earlier
    assert_equal "2025-01", @versions.resolve("2025-03").name
  end

  def test_resolve_raises_for_older_requests
    error = assert_raises(Versponse::VersionNotFoundError) { @versions.resolve("2024-01") }

    assert_match(/Available versions: 2025-01, 2025-06/, error.message)
  end

  def test_fetch_is_exact
    assert_equal "2025-01", @versions.fetch("2025-01").name
    assert_raises(Versponse::VersionNotFoundError) { @versions.fetch("2025-03") }
  end

  def test_added_versions_are_registered_globally
    assert_includes Versponse::Registry.version_names, "2025-06"
  end

  def test_resolution_is_memoized_until_cleared
    calls = 0
    resolver = lambda do |requested, names|
      calls += 1
      Versponse::VersionResolver.call(requested, names)
    end

    with_configuration(version_resolver: resolver) do
      2.times { @versions.resolve("2025-03") }
      @versions.clear_resolved
      @versions.resolve("2025-03")
    end

    assert_equal 2, calls
  end

  def test_resolve_accepts_symbols
    assert_equal "2025-01", @versions.resolve(:"2025-03").name
  end
end
