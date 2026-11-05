# frozen_string_literal: true

require "test_helper"

class DslErrorsTest < Minitest::Test
  def define(&) = Class.new(Versponse::Base, &)

  def test_property_outside_a_version
    assert_raises(Versponse::DefinitionError) { define { field :a, type: :string } }
  end

  def test_required_option
    assert_raises(Versponse::DefinitionError) { define { version("2025-09") { field :a, type: :string, required: true } } }
  end

  def test_block_and_map
    assert_raises(Versponse::DefinitionError) do
      define { version("2025-09") { field(:a, type: :string, map: "b") { |object| object } } }
    end
  end

  def test_view_outside_a_version
    assert_raises(Versponse::DefinitionError) { define { view(:embedded) {} } }
  end

  def test_include_view_outside_a_view
    assert_raises(Versponse::DefinitionError) { define { version("2025-09") { include_view :embedded } } }
  end

  def test_exclude_properties_outside_a_version
    assert_raises(Versponse::DefinitionError) { define { exclude_properties :a } }
  end

  def test_const_ignores_with_options_defaults_it_can_not_take
    klass = define do
      version "2025-09" do
        with_options type: :string, nullable: true do
          field :a
          const :k, value: "x"
        end
      end
    end

    assert_equal({"a" => nil, "k" => "x"}, klass.serialize({a: nil}, version: "2025-09"))
  end

  def test_class_level_options_must_come_before_versions
    assert_raises(Versponse::DefinitionError) do
      define do
        version("2025-09") { field :a, type: :string }
        description "late"
      end
    end
  end

  def test_classes_without_versions_can_be_subclassed
    base = define
    child = Class.new(base) { version("2025-09") { field :a, type: :string } }

    assert_equal({"a" => "x"}, child.serialize({a: "x"}, version: "2025-09"))
  end

  def test_classes_with_versions_can_not_be_subclassed
    parent = define { version("2025-09") { field :a, type: :string } }

    assert_raises(Versponse::DefinitionError) { Class.new(parent) }
  end
end
