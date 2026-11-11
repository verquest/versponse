# frozen_string_literal: true

require "test_helper"

class CollapseIfTest < Minitest::Test
  Stage = Struct.new(:public_id, :name, :archived)
  Deal = Struct.new(:id, :stage, :stages)
  Feed = Struct.new(:resource)

  class StageResponse < Versponse::Base
    version "2025-09" do
      identifier :id, map: "public_id", collapse_if: ->(stage) { !stage.archived }
      field :name, type: :string
    end

    version "2026-01"

    version "2026-03" do
      identifier :id, map: "public_id"
    end
  end

  class DealResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      reference :stage, from: StageResponse, expandable: true
      collection :stages, item: StageResponse, expandable: true
    end
  end

  class FeedResponse < Versponse::Base
    version "2025-09" do
      one_of :resource, expandable: true do
        reference from: StageResponse, match: Stage
      end
    end
  end

  class ContextStageResponse < Versponse::Base
    version "2025-09" do
      identifier :id, collapse_if: ->(_stage, context) { context[:collapse] }
      field :name, type: :string
    end
  end

  class ContextDealResponse < Versponse::Base
    version "2025-09" do
      reference :stage, from: ContextStageResponse, expandable: true
    end
  end

  class ListResponse < Versponse::Base
    version "2025-09" do
      collection :items do
        one_of expandable: true do
          reference from: StageResponse, match: Stage
        end
      end
    end
  end

  class DiscriminatedStageResponse < Versponse::Base
    version "2025-09" do
      identifier :id, map: "public_id", collapse_if: ->(stage) { !stage.archived }
      const :object, value: "stage"
      field :name, type: :string
    end
  end

  class DiscriminatedFeedResponse < Versponse::Base
    version "2025-09" do
      one_of :resource, discriminator: "object", expandable: true do
        reference from: DiscriminatedStageResponse, match: Stage
      end
    end
  end

  Pipeline = Struct.new(:id, :name)
  PipelineStage = Struct.new(:id, :name, :archived, :pipeline)
  PipelineDeal = Struct.new(:stage, :stages)

  class PipelineResponse < Versponse::Base
    version "2025-09" do
      identifier :id
      field :name, type: :string
    end
  end

  # Records each call in context[:calls]
  class PipelineStageResponse < Versponse::Base
    version "2025-09" do
      identifier :id, collapse_if: lambda { |stage, context|
        context[:calls]&.push(stage.name)
        !stage.archived
      }
      field :name, type: :string
      reference :pipeline, from: PipelineResponse, expandable: true
    end
  end

  class PipelineDealResponse < Versponse::Base
    version "2025-09" do
      reference :stage, from: PipelineStageResponse, expandable: true
      collection :stages, item: PipelineStageResponse, expandable: true
    end
  end

  def open_stage = Stage.new("s1", "Open", false)

  def archived_stage = Stage.new(nil, "Won", true)

  def deal(stage, stages, expand: nil) = DealResponse.serialize(Deal.new("d1", stage, stages), version: "2025-09", expand:)

  def define(&) = Class.new(Versponse::Base, &)

  def test_schemas_do_not_change
    expandable = {"anyOf" => [{"$ref" => "#/components/schemas/StageResponse"}, {"$ref" => "#/components/schemas/StageResponseCollapsed"}]}
    collapsed = {"type" => "object", "required" => ["id"], "properties" => {"id" => {"type" => "string"}}, "additionalProperties" => false}

    assert_equal expandable, DealResponse.to_schema(version: "2025-09")["properties"]["stage"]
    assert_equal collapsed, StageResponse.to_schema(version: "2025-09", view: :collapsed)
  end

  def test_inherited_with_the_identifier_and_reset_when_it_is_redeclared
    refute_nil StageResponse.versponse.resolve("2026-01").collapse_if
    assert_nil StageResponse.versponse.resolve("2026-03").collapse_if
  end

  def test_collapse_if_must_respond_to_call
    error = assert_raises(Versponse::DefinitionError) { define { version("2025-09") { identifier :id, collapse_if: true } } }

    assert_equal "identifier id: collapse_if: must respond to call", error.message
  end

  def test_only_one_identifier_per_version_declares_collapse_if
    error = assert_raises(Versponse::DefinitionError) do
      define do
        version "2025-09" do
          identifier :id, collapse_if: ->(object) { object }
          identifier :code, collapse_if: ->(object) { object }
        end
      end
    end

    assert_match(/2025-09: collapse_if is already declared by another identifier\z/, error.message)
  end

  def test_collapses_while_the_condition_holds
    assert_equal({"id" => "d1", "stage" => {"id" => "s1"}, "stages" => [{"id" => "s1"}]}, deal(open_stage, [open_stage]))
  end

  def test_renders_in_full_when_the_condition_fails
    assert_equal({"name" => "Won"}, deal(archived_stage, [])["stage"])
  end

  def test_one_failing_item_renders_the_whole_collection_in_full
    assert_equal [{"id" => "s1", "name" => "Open"}, {"name" => "Won"}], deal(open_stage, [open_stage, archived_stage])["stages"]
  end

  def test_expanded_associations_ignore_the_condition
    result = deal(open_stage, [open_stage], expand: %w[stage stages])

    assert_equal({"id" => "s1", "name" => "Open"}, result["stage"])
    assert_equal [{"id" => "s1", "name" => "Open"}], result["stages"]
  end

  def test_full_shape_leaves_the_identifier_out_when_the_condition_is_false
    assert_equal({"id" => "s1", "name" => "Open"}, StageResponse.serialize(open_stage, version: "2025-09"))
    assert_equal({"name" => "Won"}, StageResponse.serialize(archived_stage, version: "2025-09"))
    refute_includes StageResponse.to_schema(version: "2025-09")["required"], "id"
    assert_includes StageResponse.to_schema(version: "2026-03")["required"], "id"
  end

  def test_condition_gets_the_context
    object = {stage: {id: "s1", name: "Open"}}

    assert_equal({"stage" => {"id" => "s1"}}, ContextDealResponse.serialize(object, version: "2025-09", context: {collapse: true}))
    assert_equal({"stage" => {"name" => "Open"}}, ContextDealResponse.serialize(object, version: "2025-09", context: {collapse: false}))
  end

  def test_one_of_variants_decide_per_value
    assert_equal({"resource" => {"id" => "s1"}}, FeedResponse.serialize(Feed.new(open_stage), version: "2025-09"))
    assert_equal({"resource" => {"name" => "Won"}}, FeedResponse.serialize(Feed.new(archived_stage), version: "2025-09"))
  end

  class WithOptionsResponse < Versponse::Base
    version "2025-09" do
      with_options collapse_if: ->(object) { object } do
        identifier :id
      end
    end
  end

  def test_with_options_collapse_if_is_ignored
    assert_nil WithOptionsResponse.versponse.resolve("2025-09").collapse_if
    assert_equal({"type" => "string"}, WithOptionsResponse.to_schema(version: "2025-09", view: :collapsed)["properties"]["id"])
  end

  def test_item_one_of_decides_per_item
    result = ListResponse.serialize({items: [open_stage, archived_stage, open_stage]}, version: "2025-09")

    assert_equal [{"id" => "s1"}, {"name" => "Won"}, {"id" => "s1"}], result["items"]
  end

  def test_discriminated_one_of_keeps_the_discriminator_in_both_forms
    assert_equal({"object" => "stage", "id" => "s1"}, DiscriminatedFeedResponse.serialize(Feed.new(open_stage), version: "2025-09")["resource"])
    assert_equal({"object" => "stage", "name" => "Won"}, DiscriminatedFeedResponse.serialize(Feed.new(archived_stage), version: "2025-09")["resource"])
  end

  def pipeline_stage(archived) = PipelineStage.new("s1", archived ? "Won" : "Open", archived, Pipeline.new("p1", "Sales"))

  def pipeline_deal(stage, expand: nil, calls: nil) =
    PipelineDealResponse.serialize(PipelineDeal.new(stage, [stage]), version: "2025-09", expand:, context: {calls:})

  # The condition runs only for the identifier field of the full shape, once per stage
  def test_wildcard_renders_in_full_without_deciding_collapse
    calls = []
    result = pipeline_deal(pipeline_stage(false), expand: ["*"], calls:)
    full = {"id" => "s1", "name" => "Open", "pipeline" => {"id" => "p1", "name" => "Sales"}}

    assert_equal full, result["stage"]
    assert_equal [full], result["stages"]
    assert_equal %w[Open Open], calls
  end

  def test_nested_expansion_under_an_archived_item_rendered_in_full
    assert_equal({"name" => "Won", "pipeline" => {"id" => "p1"}}, pipeline_deal(pipeline_stage(true))["stage"])
    assert_equal({"name" => "Won", "pipeline" => {"id" => "p1", "name" => "Sales"}}, pipeline_deal(pipeline_stage(true), expand: ["stage.pipeline"])["stage"])
  end

  def test_referenced_class_without_the_version_has_no_condition
    assert_nil Versponse::References.collapse_if(StageResponse, "2025-01")
  end

  def test_fields_select_collapsed_keys_without_expand
    assert_nil DealResponse.validate_selection!(version: "2025-09", fields: %w[stage.id stages.id])
    assert_nil FeedResponse.validate_selection!(version: "2025-09", fields: %w[resource.id])
    assert_nil ListResponse.validate_selection!(version: "2025-09", fields: %w[items.id])
    assert_nil DiscriminatedFeedResponse.validate_selection!(version: "2025-09", fields: %w[resource.id resource.object])
  end

  def test_fields_beyond_collapsed_keys_still_need_expand
    {DealResponse => %w[stage.name stages.name], FeedResponse => %w[resource.name], ListResponse => %w[items.name],
     DiscriminatedFeedResponse => %w[resource.name]}.each do |klass, paths|
      error = assert_raises(Versponse::InvalidFieldsError) { klass.validate_selection!(version: "2025-09", fields: paths) }

      assert_equal paths, error.paths
      assert(error.reasons.values.all? { |reason| reason.end_with?("isn't expanded") })
    end
  end

  def test_fields_unknown_even_when_expanded_are_unknown
    {FeedResponse => "resource.nope", ListResponse => "items.nope", DiscriminatedFeedResponse => "resource.object.x"}.each do |klass, path|
      error = assert_raises(Versponse::InvalidFieldsError) { klass.validate_selection!(version: "2025-09", fields: [path]) }

      assert_equal({path => "unknown"}, error.reasons)
    end
  end

  # collapse_if renders an archived stage in full, without its identifier; fields still follows expand
  def test_fields_follow_expand_when_collapse_if_renders_full
    rendered = DealResponse.serialize(Deal.new("d1", archived_stage, [archived_stage]), version: "2025-09", fields: %w[stage.id stages.id])

    # DealResponse's id is a plain field, so it isn't selected
    assert_equal({"stage" => {}, "stages" => [{}]}, rendered)
    assert_raises(Versponse::InvalidFieldsError) do
      DealResponse.serialize(Deal.new("d1", archived_stage, []), version: "2025-09", fields: %w[stage.name])
    end
  end
end
