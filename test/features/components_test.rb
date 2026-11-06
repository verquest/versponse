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

  def test_eager_load_surfaces_reference_errors
    broken = Class.new(Versponse::Base) do
      version("2025-09") { reference :x, from: Class.new(Versponse::Base) { version("2025-09") { field :id, type: :string } }, property: :missing }
    end

    assert_raises(Versponse::DefinitionError) { Versponse.eager_load!(classes: [broken]) }
  end

  class NestedTargetResponse < Versponse::Base
    version "2025-01" do
      field :id, type: :string
      view(:embedded) { exclude_properties :id }
    end
    version("2026-01", inherit: false) { field :id, type: :string }
  end

  class NestingResponse < Versponse::Base
    version("2025-01") { object(:wrap) { reference :target, from: NestedTargetResponse, view: :embedded } }
  end

  # The parent never declares 2026-01 but serves it, and its nested class lost the view there
  def test_eager_load_checks_nested_references_at_every_served_version
    error = assert_raises(Versponse::DefinitionError) { Versponse.eager_load!(classes: [NestingResponse]) }

    assert_match(/target: view embedded not found in .*NestedTargetResponse 2026-01/, error.message)
  end
end
