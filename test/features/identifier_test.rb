# frozen_string_literal: true

require "test_helper"

class IdentifierTest < Minitest::Test
  Site = Struct.new(:public_id, :code, :name)

  class SiteResponse < Versponse::Base
    version "2025-09" do
      identifier :id, map: "public_id", description: "Site ID"
      field :name, type: :string
    end

    version "2026-01" do
      identifier :code
    end
  end

  class PlainResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
    end
  end

  class DescribedResponse < Versponse::Base
    description "A described resource"
    schema_options min_properties: 2

    version "2025-09" do
      identifier :id
      field :x, type: :string
    end
  end

  def site = Site.new("site_1", "LDS", "Leeds")

  def define(&) = Class.new(Versponse::Base, &)

  def test_collapsed_view_renders_the_identifier
    assert_equal({"id" => "site_1"}, SiteResponse.serialize(site, version: "2025-09", view: :collapsed))
  end

  def test_redeclaring_replaces_the_inherited_identifier
    assert_equal({"code" => "LDS"}, SiteResponse.serialize(site, version: "2026-01", view: :collapsed))
  end

  def test_collapsed_schema_and_component
    expected = {"type" => "object", "required" => ["id"], "properties" => {"id" => {"type" => "string", "description" => "Site ID"}}, "additionalProperties" => false}

    assert_equal expected, SiteResponse.to_schema(version: "2025-09", view: :collapsed)
    assert_equal "SiteResponseCollapsed", SiteResponse.component_name(view: :collapsed)
    assert_includes Versponse.components(version: "2025-09", classes: [SiteResponse]).keys, "SiteResponseCollapsed"
  end

  def test_collapsed_schema_ignores_the_class_description_and_schema_options
    schema = DescribedResponse.to_schema(version: "2025-09", view: :collapsed)

    refute schema.key?("description")
    refute schema.key?("minProperties")
  end

  def test_identifier_uses_with_options_defaults
    klass = define do
      version "2025-09" do
        with_options nullable: true do
          identifier :id
        end
      end
    end

    assert_equal({"id" => nil}, klass.serialize({id: nil}, version: "2025-09", view: :collapsed))
  end

  def test_view_names_include_collapsed_only_with_an_identifier
    assert_equal %i[default collapsed], SiteResponse.versponse.resolve("2025-09").view_names
    assert_equal %i[default], PlainResponse.versponse.resolve("2025-09").view_names
  end

  # Rendering asks for a view the class doesn't have, so it's the same error as any unknown view
  def test_collapsed_without_an_identifier_raises
    error = assert_raises(Versponse::ViewNotFoundError) { PlainResponse.serialize({id: "x"}, version: "2025-09", view: :collapsed) }

    assert_equal "IdentifierTest::PlainResponse 2025-09 has no identifier, so it has no collapsed view. Available views: default", error.message
  end

  def test_full_shape_renders_the_identifier
    assert_equal({"id" => "site_1", "name" => "Leeds"}, SiteResponse.serialize(site, version: "2025-09"))
  end

  def test_full_schema_describes_the_identifier
    schema = SiteResponse.to_schema(version: "2025-09")

    assert_equal({"type" => "string", "description" => "Site ID"}, schema["properties"]["id"])
    assert_includes schema["required"], "id"
  end

  def test_redeclared_identifier_adds_its_property
    assert_equal({"code" => "LDS", "id" => "site_1", "name" => "Leeds"}, SiteResponse.serialize(site, version: "2026-01").sort.to_h)
  end

  def test_property_with_the_identifier_key_raises
    error = assert_raises(Versponse::DefinitionError) do
      define do
        version "2025-09" do
          identifier :id
          field :id, type: :string
        end
      end
    end

    assert_match(/id is declared by identifier/, error.message)
  end

  def test_definition_errors
    assert_raises(Versponse::DefinitionError) { define { identifier :id } }
    assert_raises(Versponse::DefinitionError) { define { version("2025-09") { identifier :id, if: ->(object) { object } } } }
    assert_raises(Versponse::DefinitionError) { define { version("2025-09") { view(:collapsed) {} } } }
  end
end
