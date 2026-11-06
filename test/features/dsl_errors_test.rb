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

  def test_conditions_must_be_callable
    assert_raises(Versponse::DefinitionError) { define { version("2025-09") { field :a, type: :string, if: :a? } } }
    assert_raises(Versponse::DefinitionError) { define { version("2025-09") { field :a, type: :string, unless: "a" } } }
  end

  def test_symbol_procs_read_from_the_object
    klass = define do
      version("2025-09") { field(:name, type: :string, if: :name.to_proc, &:name) }
    end

    assert_equal({"name" => "Leeds"}, klass.serialize(Struct.new(:name).new("Leeds"), version: "2025-09"))
  end

  def test_unknown_options_raise
    error = assert_raises(Versponse::DefinitionError) do
      define { version("2025-09") { field :id, type: :string, mapp: "name", nulable: true } }
    end

    assert_equal "id: unknown options mapp:, nulable: (did you mean map:, nullable:?)", error.message
  end

  def test_schema_keywords_and_extensions_are_accepted
    klass = define do
      version("2025-09") { field :id, type: :string, max_length: 10, read_only: true, "x-internal": true }
    end

    assert_equal({"type" => "string", "maxLength" => 10, "readOnly" => true, "x-internal" => true}, klass.to_schema(version: "2025-09")["properties"]["id"])
  end

  def test_with_options_collapse_if_stays_on_identifiers
    klass = define do
      version "2025-09" do
        with_options collapse_if: ->(_object) { true } do
          identifier :id, type: :string
          field :name, type: :string
        end
      end
    end

    assert_equal({"type" => "string"}, klass.to_schema(version: "2025-09")["properties"]["name"])
  end

  def test_duplicate_version_raises
    error = assert_raises(Versponse::DefinitionError) do
      define do
        version("2025-09") { field :a, type: :string }
        version("2025-09") { field :b, type: :string }
      end
    end

    assert_equal "AnonymousResponse declares version 2025-09 twice", error.message
  end

  def test_duplicate_view_in_a_version_raises
    error = assert_raises(Versponse::DefinitionError) do
      define do
        version "2025-09" do
          field :a, type: :string
          view :a
          view :a
        end
      end
    end

    assert_equal "AnonymousResponse 2025-09 declares view a twice", error.message
  end

  # The collapsed shape would keep rendering it, so the identifiers are redeclared instead
  def test_excluding_an_identifier_raises
    message = "AnonymousResponse 2025-10: id is an identifier; redeclare the identifiers instead of excluding it"
    error = assert_raises(Versponse::DefinitionError) do
      define do
        version("2025-09") { identifier :id, type: :string }
        version("2025-10") { exclude_properties :id }
      end
    end
    inherited = assert_raises(Versponse::DefinitionError) do
      define do
        version("2025-09") { identifier :id, type: :string }
        version "2025-10", exclude_properties: [:id]
      end
    end

    assert_equal message, error.message
    assert_equal message, inherited.message
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

  def test_enum_takes_type_from_with_options
    klass = define do
      version "2025-09" do
        with_options type: :integer, nullable: true do
          enum :level, values: [1, 2]
          enum :status, type: :string, values: %w[a]
        end
      end
    end
    properties = klass.to_schema(version: "2025-09")["properties"]

    assert_equal({"type" => %w[integer null], "enum" => [1, 2, nil]}, properties["level"])
    assert_equal({"type" => %w[string null], "enum" => ["a", nil]}, properties["status"])
  end

  def test_enum_without_type_infers_it
    klass = define { version("2025-09") { enum :status, values: %w[a] } }

    assert_equal({"type" => "string", "enum" => ["a"]}, klass.to_schema(version: "2025-09")["properties"]["status"])
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
