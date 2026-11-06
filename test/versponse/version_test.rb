# frozen_string_literal: true

require "test_helper"

class Versponse::VersionTest < Minitest::Test
  def field(name) = Versponse::Properties::Field.new(name:, type: :string)

  def build(name = "2025-09") = Versponse::Version.new(name:, owner: "UserResponse")

  def test_add_and_remove
    version = build
    version.add(field(:a))
    version.add(field(:b))
    version.remove(:a)

    assert_equal ["b"], version.properties.keys
  end

  def test_remove_unknown_raises
    error = assert_raises(Versponse::DefinitionError) { build.remove(:a) }

    assert_match(/UserResponse 2025-09/, error.message)
  end

  def test_copy_from_excludes_properties_and_inherits_views
    old = build("2025-01")
    old.add(field(:a))
    old.add(field(:b))
    old.add_view(Versponse::View.new(name: :embedded))
    old.finalize!

    version = build
    version.copy_from(old, exclude_properties: [:a])

    assert_equal ["b"], version.properties.keys
    assert_equal %i[default embedded], version.view_names
  end

  def test_copy_from_rejects_unknown_excludes
    old = build("2025-01").tap { |v| v.add(field(:a)) }.finalize!

    assert_raises(Versponse::DefinitionError) { build.copy_from(old, exclude_properties: [:typo]) }
  end

  def test_finalize_freezes
    version = build.tap { |v| v.add(field(:a)) }
    version.finalize!

    assert_predicate version, :frozen?
    assert_predicate version.properties, :frozen?
  end

  def test_unknown_view
    error = assert_raises(Versponse::ViewNotFoundError) { build.properties_for(:missing) }

    assert_match(/Available views: default/, error.message)
  end

  def test_default_view_is_reserved
    assert_raises(Versponse::DefinitionError) { build.add_view(Versponse::View.new(name: :default)) }
  end
end
