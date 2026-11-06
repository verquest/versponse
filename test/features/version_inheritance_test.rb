# frozen_string_literal: true

require "test_helper"

class VersionInheritanceTest < Minitest::Test
  User = Struct.new(:id, :name, :email)

  class UserResponse < Versponse::Base
    version "2025-01" do
      field :id, type: :string
      field :name, type: :string
      field :email, type: :string
    end

    version "2025-06", exclude_properties: %i[email] do
      field :name, type: :string, map: "email"
    end

    version "2025-09" do
      exclude_properties :name
    end

    version "2026-01", inherit: false do
      field :id, type: :string
    end

    version "2026-03", inherit: "2025-01"
  end

  def serialize(version)
    UserResponse.serialize(User.new(id: "u1", name: "Ann", email: "ann@example.com"), version:)
  end

  def test_first_version
    assert_equal({"id" => "u1", "name" => "Ann", "email" => "ann@example.com"}, serialize("2025-01"))
  end

  def test_exclude_and_redeclare
    assert_equal({"id" => "u1", "name" => "ann@example.com"}, serialize("2025-06"))
  end

  def test_exclude_inside_the_block
    assert_equal({"id" => "u1"}, serialize("2025-09"))
  end

  def test_inherit_false
    assert_equal({"id" => "u1"}, serialize("2026-01"))
  end

  def test_inherit_from_a_named_version
    assert_equal serialize("2025-01"), serialize("2026-03")
  end

  def test_excluding_an_unknown_property_raises
    assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) { version("2025-01") { exclude_properties :missing } }
    end
  end

  # Like verquest: inherit: "2025-03" copies the closest earlier version, 2025-01
  def test_inherit_resolves_to_the_closest_earlier_version
    klass = Class.new(Versponse::Base) do
      version("2025-01") { field :id, type: :string }
      version("2025-02") { field :name, type: :string }
      version "2025-06", inherit: "2025-01-15"
    end

    assert_equal({"id" => "1"}, klass.serialize({id: "1", name: "x"}, version: "2025-06"))
  end

  def test_inherit_before_every_version_raises
    error = assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) do
        version("2025-01") { field :id, type: :string }
        version "2025-06", inherit: "2024-01"
      end
    end

    assert_equal "inherit: no version of AnonymousResponse at or before 2024-01 (declared: 2025-01)", error.message
  end

  def test_version_blocks_can_not_be_nested
    assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) { version("2025-01") { version("2025-02") { field :id, type: :string } } }
    end
  end
end
