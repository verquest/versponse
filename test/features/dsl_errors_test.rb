# frozen_string_literal: true

require "test_helper"

class DslErrorsTest < Minitest::Test
  include ConfigurationTestHelper

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

  def test_item_schema_options_are_checked
    error = assert_raises(Versponse::DefinitionError) { define { version("2025-09") { array :a, type: :string, item_schema_options: {mapp: 1} } } }

    assert_match(/\Aa item_schema_options: unknown options mapp:/, error.message)
  end

  def test_view_cannot_redeclare_an_identifier
    assert_raises(Versponse::DefinitionError) do
      define do
        version "2025-09" do
          identifier :id
          view(:slim) { field :id, type: :integer }
        end
      end
    end
  end

  def test_exclude_properties_without_inheritance_raises
    assert_raises(Versponse::DefinitionError) { define { version("2025-09", exclude_properties: [:a]) { field :b, type: :string } } }
    assert_raises(Versponse::DefinitionError) do
      define do
        version("2025-09") { field :a, type: :string }
        version("2025-10", inherit: false, exclude_properties: [:a]) { field :b, type: :string }
      end
    end
  end

  # A keyword the property writes itself would silently replace what the DSL declared
  def test_keywords_the_property_writes_raise
    error = assert_raises(Versponse::DefinitionError) { define { version("2025-09") { enum :a, values: %w[x y], enum: %w[z] } } }

    assert_equal "a: enum: is written by enum itself", error.message
    assert_raises(Versponse::DefinitionError) { define { version("2025-09") { const :a, value: "x", const: "y" } } }
    assert_raises(Versponse::DefinitionError) { define { version("2025-09") { object(:a, properties: {}) { field :b, type: :string } } } }
  end

  def test_unknown_class_and_version_schema_options_raise
    assert_raises(Versponse::DefinitionError) { define { schema_options foo_bar: 1 } }
    assert_raises(Versponse::DefinitionError) { define { schema_options required: [] } }
    assert_raises(Versponse::DefinitionError) { define { version("2025-09") { schema_options type: "array" } } }
  end

  # The old identifier's conditional copy goes back to a plain field once another identifier replaces it
  def test_redeclared_identifier_drops_the_old_collapse_if
    klass = define do
      version("2025-09") { identifier :id, collapse_if: ->(_object) { false } }
      version("2025-10") { identifier :uuid }
    end

    assert_equal({"id" => "1", "uuid" => "u"}, klass.serialize({id: "1", uuid: "u"}, version: "2025-10"))
    assert_includes klass.to_schema(version: "2025-10")["required"], "id"
  end

  def test_failed_nested_version_keeps_the_outer_scope
    klass = define do
      version "2025-09" do
        begin
          version("2025-10") {}
        rescue Versponse::DefinitionError
          nil
        end
        field :a, type: :string
      end
    end

    assert_equal({"a" => "x"}, klass.serialize({a: "x"}, version: "2025-09"))
  end

  def test_current_version_returning_nil_is_a_configuration_error
    klass = define { version("2025-09") { field :a, type: :string } }

    with_configuration(current_version: -> {}) do
      assert_raises(ArgumentError) { klass.serialize({a: "x"}) }
    end
  end

  def test_anonymous_classes_have_no_ref
    error = assert_raises(Versponse::DefinitionError) { define { version("2025-09") { field :a, type: :string } }.to_ref }

    assert_match(/anonymous/, error.message)
  end
end
