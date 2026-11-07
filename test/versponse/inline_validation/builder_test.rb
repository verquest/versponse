# frozen_string_literal: true

require "test_helper"

class Versponse::InlineValidation::BuilderTest < Minitest::Test
  include ConfigurationTestHelper

  class ItemResponse < Versponse::Base
    version("2025-09") { identifier :id }
  end

  def define(&)
    Class.new(Versponse::Base) { version("2025-09", &) }
  end

  def validating_plan(klass)
    klass.versponse.validating_plan(version: "2025-09")
  end

  # Child steps of a validating plan by key: proven nested steps render with validating plans, others are checked
  def step(klass, key)
    validating_plan(klass).steps.find { |candidate| candidate.key == key }
  end

  def test_plain_classes_get_checked_leaf_steps
    klass = define do
      field :name, type: :string
      field :at, type: :string, format: "date-time"
      field(:shout, type: :string) { |object| object[:name].upcase }
    end

    assert_equal [Versponse::Steps::CheckedRead, Versponse::Steps::CheckedReadFormatted, Versponse::Steps::CheckedValue],
      validating_plan(klass).steps.map(&:class)
  end

  def test_unproven_object_schemas_have_no_validating_plan
    extra_keyword = Class.new(Versponse::Base) do
      schema_options min_properties: 1
      version("2025-09") { field :name, type: :string }
    end

    assert_nil validating_plan(extra_keyword)
  end

  def test_open_objects_have_no_validating_plan
    with_configuration(default_additional_properties: true) do
      assert_nil validating_plan(define { field :name, type: :string })
    end
  end

  def test_proven_nested_forms_render_with_validating_plans
    klass = define do
      reference :item, from: ItemResponse
      reference :maybe_item, from: ItemResponse, nullable: true
      collection :items, item: ItemResponse
      collection :maybe_items, item: ItemResponse, nullable: true
      reference :expandable_item, from: ItemResponse, expandable: true
      object(:inline) { field :x, type: :string }
    end

    %w[item maybe_item items maybe_items expandable_item inline].each do |key|
      assert_kind_of Versponse::Steps::Nested, step(klass, key), key
      validating = step(klass, key).plans.all? { |plan| plan.is_a?(Versponse::Plan) && plan.steps.all? { |child| child.class.name.include?("Checked") } }

      assert validating, "#{key} renders with validating plans"
    end
  end

  def test_nil_fails_only_where_the_schema_rejects_nil
    klass = define do
      reference :item, from: ItemResponse
      reference :maybe_item, from: ItemResponse, nullable: true
    end
    plan = validating_plan(klass)

    assert Versponse::InlineValidation.run { plan.call({item: nil, maybe_item: nil}, {}) }
    refute Versponse::InlineValidation.run { plan.call({item: {id: "1"}, maybe_item: nil}, {}) }
  end

  def test_unproven_nested_values_are_checked_after_rendering
    klass = Class.new(Versponse::Base) do
      version "2025-09" do
        one_of(:either) { reference from: ItemResponse, match: Hash }
        collection(:mixed) { one_of { reference from: ItemResponse, match: Hash } }
      end
    end

    assert_kind_of Versponse::Steps::Checked, step(klass, "either")
    assert_kind_of Versponse::Steps::Checked, step(klass, "mixed")
  end

  class TreeResponse < Versponse::Base
    version "2025-09" do
      field :name, type: :string
      collection :children, item: TreeResponse
    end
  end

  # The recursive reference is a $ref, so it is checked after rendering, and building terminates
  def test_recursive_classes_check_their_back_references
    assert_kind_of Versponse::Steps::Checked, validating_plan(TreeResponse).steps.last
  end
end
