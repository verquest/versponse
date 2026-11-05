# frozen_string_literal: true

require "test_helper"

class ComponentsTest < Minitest::Test
  class WidgetResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      field :name, type: :string

      view :embedded do
        exclude_properties :name
      end
    end
  end

  class GadgetResponse < Versponse::Base
    version "2026-01" do
      field :id, type: :string
    end
  end

  def test_collects_every_view_of_classes_covering_the_version
    components = Versponse.components(version: "2025-09", classes: [WidgetResponse, GadgetResponse])

    assert_equal %w[WidgetResponse WidgetResponseEmbedded], components.keys
    assert_equal WidgetResponse.to_schema(version: "2025-09", view: :embedded), components["WidgetResponseEmbedded"]
  end

  def test_skips_classes_without_versions
    assert_empty Versponse.components(version: "2025-09", classes: [Class.new(Versponse::Base)])
  end

  def test_duplicate_names_raise
    duplicate = Class.new(Versponse::Base) do
      def self.base_component_name = "WidgetResponse"

      version("2025-09") { field :id, type: :string }
    end

    assert_raises(Versponse::DefinitionError) { Versponse.components(version: "2025-09", classes: [WidgetResponse, duplicate]) }
  end

  def test_registry_lists_named_live_classes
    assert_includes Versponse::Registry.classes, WidgetResponse
    refute_includes Versponse::Registry.classes, Class.new(Versponse::Base)
  end

  def test_eager_load_surfaces_view_errors
    broken = Class.new(Versponse::Base) do
      version "2025-09" do
        field :id, type: :string
        view(:a) { include_view :a }
      end
    end

    assert_raises(Versponse::InvalidViewError) { Versponse.eager_load!(classes: [broken]) }
  end
end
