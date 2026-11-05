# frozen_string_literal: true

require "test_helper"

class IdentifierTest < Minitest::Test
  Site = Struct.new(:public_id, :code, :name)

  class SiteResponse < Versponse::Base
    version "2025-09" do
      identifier :id, map: "public_id"
      field :id, type: :string, map: "public_id"
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
      field :id, type: :string
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
    expected = {"type" => "object", "required" => ["id"], "properties" => {"id" => {"type" => "string"}}, "additionalProperties" => false}

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
    assert_equal %i[default collapsed], SiteResponse.resolve("2025-09").view_names
    assert_equal %i[default], PlainResponse.resolve("2025-09").view_names
  end

  def test_collapsed_without_an_identifier_raises
    assert_raises(Versponse::DefinitionError) { PlainResponse.serialize({id: "x"}, version: "2025-09", view: :collapsed) }
  end

  def test_definition_errors
    assert_raises(Versponse::DefinitionError) { define { identifier :id } }
    assert_raises(Versponse::DefinitionError) { define { version("2025-09") { identifier :id, if: ->(object) { object } } } }
    assert_raises(Versponse::DefinitionError) { define { version("2025-09") { view(:collapsed) {} } } }
  end
end
