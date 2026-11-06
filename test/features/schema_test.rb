# frozen_string_literal: true

require "test_helper"

class SchemaTest < Minitest::Test
  include ConfigurationTestHelper

  class ProductResponse < Versponse::Base
    description "A product"

    version "2025-09" do
      field :id, type: :string, description: "Product ID"
      field :price, type: :integer, nullable: true
      field :discount, type: :integer, if: ->(product) { product[:discount] }

      view :compact do
        exclude_properties :price
      end
    end

    version "2026-01" do
      description "A product, v2"
      schema_options deprecated: true
    end
  end

  class RenamedResponse < Versponse::Base
    def self.base_component_name = super.delete_suffix("Response")

    version "2025-09" do
      field :id, type: :string
    end
  end

  module Nested
    class DeepResponse < Versponse::Base
      version "2025-09" do
        field :id, type: :string
      end
    end
  end

  def test_to_schema
    expected = {
      "type" => "object",
      "description" => "A product",
      "required" => %w[id price],
      "properties" => {
        "id" => {"type" => "string", "description" => "Product ID"},
        "price" => {"type" => %w[integer null]},
        "discount" => {"type" => "integer"}
      },
      "additionalProperties" => false
    }

    assert_equal expected, ProductResponse.to_schema(version: "2025-09")
  end

  def test_view_schema
    schema = ProductResponse.to_schema(version: "2025-09", view: :compact)

    assert_equal %w[id], schema["required"]
    assert_equal %w[id discount], schema["properties"].keys
  end

  def test_version_description_and_schema_options
    schema = ProductResponse.to_schema(version: "2026-01")

    assert_equal "A product, v2", schema["description"]
    assert schema["deprecated"]
  end

  def test_openapi30_nullable
    with_configuration(json_schema_version: :openapi30) do
      assert_equal({"type" => "integer", "nullable" => true}, ProductResponse.to_schema(version: "2025-09")["properties"]["price"])
    end
  end

  # An enum lists null itself, or validators reject it despite nullable
  def test_openapi30_nullable_enum_lists_null
    with_configuration(json_schema_version: :openapi30) do
      klass = Class.new(Versponse::Base) { version("2025-09") { enum :status, values: %w[a b], nullable: true } }
      schema = klass.to_schema(version: "2025-09")["properties"]["status"]

      assert_equal({"type" => "string", "nullable" => true, "enum" => ["a", "b", nil]}, schema)
      assert JSONSchemer.schema(schema, meta_schema: JSONSchemer::OpenAPI30::BASE_URI.to_s).valid?(nil)
    end
  end

  # Settings that change output reset the caches themselves, so a later change isn't ignored
  def test_changing_settings_resets_cached_schemas
    config = Versponse.configuration
    klass = Class.new(Versponse::Base) { version("2025-09") { field :id, type: :string } }

    refute klass.to_schema(version: "2025-09")["additionalProperties"]
    config.default_additional_properties = true

    assert klass.to_schema(version: "2025-09")["additionalProperties"]
  ensure
    config.default_additional_properties = false
  end

  # Defining a class bumps the cache generation; other classes rebuild on next use instead of eagerly
  def test_defining_a_class_invalidates_other_classes_lazily
    klass = Class.new(Versponse::Base) { version("2025-09") { field :id, type: :string } }
    plan = klass.versponse.plan(version: "2025-09")
    generation = Versponse.cache_generation
    Class.new(Versponse::Base) { version("2025-09") { field :x, type: :string } }

    assert_operator Versponse.cache_generation, :>, generation
    refute_same plan, klass.versponse.plan(version: "2025-09")
  end

  class AppResponse < Versponse::Base
    description "Shared"
    schema_options additional_properties: true
  end

  class InheritingResponse < AppResponse
    version("2025-09") { field :id, type: :string }
  end

  # Like supported_versions, class-level settings of an abstract base reach its subclasses
  def test_subclasses_inherit_description_and_schema_options
    schema = InheritingResponse.to_schema(version: "2025-09")

    assert_equal "Shared", schema["description"]
    assert schema["additionalProperties"]
  end

  # nullable: adds nil to an enum: option, as the enum property does
  def test_nullable_field_enum_lists_nil
    klass = Class.new(Versponse::Base) { version("2025-09") { field :s, type: :string, enum: %w[a b], nullable: true } }

    assert_equal ["a", "b", nil], klass.to_schema(version: "2025-09")["properties"]["s"]["enum"]
    assert_equal ["a", "b", nil], klass.to_validation_schema(version: "2025-09")["properties"]["s"]["enum"]
  end

  # Draft 4 and OpenAPI 3.0 have no const: every generated const becomes a one-value enum, options included
  def test_const_options_become_enums_without_const_keyword
    klass = Class.new(Versponse::Base) do
      version "2025-09" do
        field :fixed, type: :string, const: "a"
        field :choice, type: :integer, any_of: [{const: 0}, {minimum: 5}]
      end
    end

    %i[draft4 openapi30].each do |json_schema_version|
      with_configuration(json_schema_version:) do
        [klass.to_schema(version: "2025-09"), klass.to_validation_schema(version: "2025-09")].each do |schema|
          assert_equal({"type" => "string", "enum" => ["a"]}, schema["properties"]["fixed"], json_schema_version)
          assert_equal [{"enum" => [0]}, {"minimum" => 5}], schema["properties"]["choice"]["anyOf"]
        end
      end
    end
  end

  # const allows one value, so nullable turns it into an enum of that value and null
  def test_nullable_const_option_accepts_null
    klass = Class.new(Versponse::Base) { version("2025-09") { field :c, type: :string, nullable: true, const: "a" } }

    assert_equal({"type" => %w[string null], "enum" => ["a", nil]}, klass.to_schema(version: "2025-09")["properties"]["c"])
    with_configuration(validate_output: true) do
      assert_equal({"c" => nil}, klass.serialize({c: nil}, version: "2025-09"))
    end
  end

  # Class-level settings are looked up when schemas are built, so a parent changed later still reaches
  # its subclasses, and schema_options merge with the subclass winning per key
  def test_class_settings_are_inherited_live_and_merged
    parent = Class.new(Versponse::Base) { schema_options deprecated: true, title: "Parent" }
    child = Class.new(parent) do
      schema_options title: "Child"
      version("2025-09") { field :id, type: :string }
    end
    parent.class_exec { description "Added later" }
    schema = child.to_schema(version: "2025-09")

    assert_equal "Added later", schema["description"]
    assert schema["deprecated"]
    assert_equal "Child", schema["title"]
  end

  def test_version_settings_win_over_inherited_ones
    parent = Class.new(Versponse::Base) { schema_options title: "Parent" }
    child = Class.new(parent) { version("2025-09") { schema_options(title: "Version") && description("Version") } }

    assert_equal %w[Version Version], child.to_schema(version: "2025-09").values_at("title", "description")
  end

  def test_component_names
    assert_equal "ProductResponse", ProductResponse.component_name
    assert_equal "ProductResponseCompact", ProductResponse.component_name(view: :compact)
    assert_equal "Renamed", RenamedResponse.component_name
    assert_equal "NestedDeepResponse", Nested::DeepResponse.component_name
  end

  def test_to_ref
    assert_equal "#/components/schemas/ProductResponseCompact", ProductResponse.to_ref(view: :compact)
    assert_equal "#/components/schemas/ProductResponse/properties/id", ProductResponse.to_ref(property: :id)
  end

  def test_validation_schema
    assert_equal ProductResponse.to_schema(version: "2025-09"), ProductResponse.to_validation_schema(version: "2025-09")
    assert_equal({"type" => "string", "description" => "Product ID"}, ProductResponse.to_validation_schema(version: "2025-09", property: :id))
  end

  def test_schemas_are_cached_and_deeply_frozen
    schema = ProductResponse.to_schema(version: "2025-09")

    assert_same schema, ProductResponse.to_schema(version: "2025-09")
    assert_predicate schema["properties"]["id"], :frozen?
  end
end
