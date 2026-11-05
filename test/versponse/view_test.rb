# frozen_string_literal: true

require "test_helper"

class Versponse::ViewTest < Minitest::Test
  def field(name) = Versponse::Properties::Field.new(name:, type: :string)

  def setup
    @version = Versponse::Version.new(name: "2025-09", owner: "UserResponse")
    %i[id name site].each { |name| @version.add(field(name)) }
  end

  def keys(view) = view.resolve(@version).map(&:key)

  def test_exclude
    view = Versponse::View.new(name: :embedded)
    view.exclude([:site])

    assert_equal %w[id name], keys(view)
  end

  def test_view_only_property
    view = Versponse::View.new(name: :admin)
    view.add(field(:secret))

    assert_equal %w[id name site secret], keys(view)
  end

  def test_include_view_applies_its_operations
    embedded = Versponse::View.new(name: :embedded).tap { |view| view.exclude([:site]) }
    compact = Versponse::View.new(name: :compact).tap do |view|
      view.include_view(:embedded)
      view.exclude([:name])
    end
    @version.add_view(embedded)
    @version.add_view(compact)

    assert_equal %w[id], keys(compact)
  end

  def test_include_cycle_raises
    first = Versponse::View.new(name: :a).tap { |view| view.include_view(:b) }
    @version.add_view(first)
    @version.add_view(Versponse::View.new(name: :b).tap { |view| view.include_view(:a) })

    error = assert_raises(Versponse::InvalidViewError) { keys(first) }

    assert_match(/a -> b -> a/, error.message)
  end

  def test_check_excludes
    view = Versponse::View.new(name: :embedded).tap { |v| v.exclude([:missing]) }

    assert_raises(Versponse::PropertyNotFoundError) { view.check_excludes!(%w[id], "UserResponse 2025-09") }
    assert_nil view.for_next_version.check_excludes!(%w[id], "UserResponse 2025-10")
  end

  def test_inherited_view_ignores_removed_properties
    view = Versponse::View.new(name: :embedded).tap { |v| v.exclude([:site]) }
    newer = Versponse::Version.new(name: "2026-01", owner: "UserResponse")
    %i[id name].each { |name| newer.add(field(name)) }

    assert_equal %w[id name], view.for_next_version.resolve(newer).map(&:key)
  end

  def test_copy_for_next_version_does_not_share_state
    view = Versponse::View.new(name: :embedded)
    view.for_next_version.exclude([:site])

    assert_equal %w[id name site], keys(view)
  end

  def test_include_view_default_is_rejected
    assert_raises(Versponse::DefinitionError) { Versponse::View.new(name: :embedded).include_view(:default) }
  end
end
