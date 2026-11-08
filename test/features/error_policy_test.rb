# frozen_string_literal: true

require "test_helper"

class ErrorPolicyTest < Minitest::Test
  include ConfigurationTestHelper

  Boom = Class.new(StandardError)
  Item = Struct.new(:id)
  FAIL = ->(_item) { raise Boom, "boom" }

  class LenientResponse < Versponse::Base
    on_error :nullify

    version "2025-09" do
      field :name, type: :string, nullable: true, &FAIL
    end
  end

  class StrictInLenientResponse < Versponse::Base
    on_error :nullify

    version "2025-09" do
      field :count, type: :integer, &FAIL
    end
  end

  class OwnRaiseResponse < Versponse::Base
    on_error :nullify

    version "2025-09" do
      field :name, type: :string, nullable: true, on_error: :raise, &FAIL
    end
  end

  class HandledResponse < Versponse::Base
    on_error ->(_error, _item, key, _context) { "no #{key}" }

    version "2025-09" do
      field :name, type: :string, &FAIL
      field :note, type: :string, &FAIL
    end
  end

  class SourceResponse < Versponse::Base
    version "2025-09" do
      field :name, type: :string, nullable: true, &FAIL
      field :note, type: :string, on_error: ->(_error, _item, key, _context) { "no #{key}" }, &FAIL
    end
  end

  class ReusingResponse < Versponse::Base
    on_error :nullify

    version "2025-09" do
      reference :title, from: SourceResponse, property: :name
      reference :remark, from: SourceResponse, property: :note
    end
  end

  class OmittedSourceResponse < Versponse::Base
    version "2025-09" do
      field :name, type: :string, if: ->(_item) { true }, on_error: :omit, &FAIL
    end
  end

  # The copy is required (no if:), so the reused :omit doesn't fit it
  class RequiredReuseResponse < Versponse::Base
    version "2025-09" do
      reference :title, from: OmittedSourceResponse, property: :name
    end
  end

  class ConditionalReuseResponse < Versponse::Base
    version "2025-09" do
      reference :title, from: OmittedSourceResponse, property: :name, if: ->(_item) { true }
    end
  end

  class HandledReuseResponse < Versponse::Base
    on_error ->(_error, _item, key, _context) { "no #{key}" }

    version "2025-09" do
      reference :title, from: OmittedSourceResponse, property: :name
    end
  end

  class FailingChildResponse < Versponse::Base
    version "2025-09" do
      field :name, type: :string, &FAIL
    end
  end

  class MissingChildResponse < Versponse::Base
    version "2025-09" do
      field :missing, type: :string
    end
  end

  class VersponseErrorChildResponse < Versponse::Base
    version "2025-09" do
      field(:name, type: :string) { |_item| raise Versponse::Error, "no" }
    end
  end

  class RecoveringChildResponse < Versponse::Base
    version "2025-09" do
      field :name, type: :string, nullable: true, on_error: :nullify, &FAIL
    end
  end

  class ExplicitParentResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      reference :child, from: FailingChildResponse, map: ".", nullable: true, on_error: :nullify
    end
  end

  class ClassLevelParentResponse < Versponse::Base
    on_error :nullify

    version "2025-09" do
      reference :child, from: FailingChildResponse, map: ".", nullable: true
    end
  end

  def define(&block)
    Class.new(Versponse::Base) { version("2025-09", &block) }
  end

  def render(klass, item = Item.new("i1")) = klass.serialize(item, version: "2025-09")

  def test_nullify_needs_nullable
    error = assert_raises(Versponse::DefinitionError) { define { field :total, type: :integer, on_error: :nullify } }

    assert_equal "total: on_error: :nullify needs nullable: true", error.message
  end

  def test_omit_needs_a_condition
    error = assert_raises(Versponse::DefinitionError) { define { field :total, type: :integer, on_error: :omit } }

    assert_equal "total: on_error: :omit needs if: or unless:", error.message
  end

  def test_unknown_policy_or_handler_arity
    error = assert_raises(Versponse::DefinitionError) { define { field :total, type: :integer, on_error: :ignore } }

    assert_equal "total: on_error: must be :raise, :nullify, :omit or a callable taking (error, object, key, context)", error.message
    error = assert_raises(Versponse::DefinitionError) { define { field :total, type: :integer, on_error: ->(_error) { 0 } } }

    assert_equal "total: on_error: must be :raise, :nullify, :omit or a callable taking (error, object, key, context)", error.message
  end

  def test_with_options_applies_on_error_to_each_property
    error = assert_raises(Versponse::DefinitionError) do
      define do
        with_options on_error: :nullify do
          field :name, type: :string, nullable: true
          field :total, type: :integer
        end
      end
    end

    assert_equal "total: on_error: :nullify needs nullable: true", error.message
  end

  def test_valid_declarations
    klass = define do
      field :a, type: :integer, nullable: true, on_error: :nullify
      field :b, type: :integer, if: ->(_) { true }, on_error: :omit
      field :c, type: :integer, on_error: :raise
      field :d, type: :integer, on_error: ->(_error, _object, _key, _context) { 0 }
    end

    assert_equal %i[nullify omit raise], klass.versponse.resolve("2025-09").properties_for(:default).first(3).map(&:on_error)
  end

  def test_nullify_writes_nil_and_the_render_goes_on
    klass = define do
      field :name, type: :string, nullable: true, on_error: :nullify, &FAIL
      field :id, type: :string
    end

    assert_equal({"name" => nil, "id" => "i1"}, render(klass))
  end

  def test_omit_leaves_the_key_out
    klass = define do
      field :id, type: :string
      field :name, type: :string, if: ->(_) { true }, on_error: :omit, &FAIL
    end

    assert_equal({"id" => "i1"}, render(klass))
  end

  def test_handler_value_is_written
    klass = define do
      field :name, type: :string, on_error: ->(error, item, key, _context) { "#{key}:#{error.message}:#{item.id}" }, &FAIL
    end

    assert_equal({"name" => "name:boom:i1"}, render(klass))
  end

  def test_handler_value_is_validated
    klass = define { field :name, type: :string, on_error: ->(*) { 1 }, &FAIL }

    assert_raises(Versponse::InvalidOutputError) { render(klass) }
  end

  # nullable: never changes a declared any_of, so null fails this schema; a recovered nil is validated in full
  def test_nullify_is_validated_in_full
    klass = define { field :name, type: :string, nullable: true, any_of: [{type: "string"}], on_error: :nullify, &FAIL }

    assert_raises(Versponse::InvalidOutputError) { render(klass) }
  end

  def test_what_is_recovered
    assert_equal({"name" => nil}, render(define { field :name, type: :string, nullable: true, on_error: :nullify }, Object.new))
    assert_raises(Versponse::ExtractionError) { render(define { field :name, type: :string }, Object.new) }
    versponse_error = define do
      field(:name, type: :string, nullable: true, on_error: :nullify) { |_item| raise Versponse::Error, "no" }
    end

    assert_raises(Versponse::Error) { render(versponse_error) }
  end

  def test_class_level_policy_recovers_properties_it_fits
    assert_equal({"name" => nil}, render(LenientResponse))
    assert_raises(Boom) { render(StrictInLenientResponse) }
    assert_raises(Boom) { render(OwnRaiseResponse) }
  end

  def test_class_level_handler_applies_to_every_property
    assert_equal({"name" => "no name", "note" => "no note"}, render(HandledResponse))
  end

  def test_config_level_policies
    nullable = define { field :name, type: :string, nullable: true, &FAIL }
    conditional = define { field :name, type: :string, if: ->(_) { true }, &FAIL }
    raising = Class.new(Versponse::Base) do
      on_error :raise
      version("2025-09") { field :name, type: :string, nullable: true, &FAIL }
    end

    with_configuration(on_error: :nullify) do
      assert_equal({"name" => nil}, render(nullable))
      assert_raises(Boom) { render(raising) }
    end
    with_configuration(on_error: :omit) { assert_empty(render(conditional)) }
    with_configuration(on_error: ->(_error, _item, key, _context) { "no #{key}" }) { assert_equal({"name" => "no name"}, render(conditional)) }
  end

  def test_with_options_on_error_applies_to_each_property
    klass = define do
      with_options on_error: :nullify, nullable: true do
        field :name, type: :string, &FAIL
        field :note, type: :string, &FAIL
      end
    end

    assert_equal({"name" => nil, "note" => nil}, render(klass))
  end

  def test_reference_property_resolves_against_the_reused_property
    assert_equal({"title" => nil, "remark" => "no remark"}, render(ReusingResponse))
  end

  # A reused policy applies only where it keeps the copy within its schema; otherwise the class and config decide
  def test_a_reused_policy_applies_only_where_it_fits
    assert_raises(Boom) { render(RequiredReuseResponse) }
    assert_equal({}, render(ConditionalReuseResponse))
    assert_equal({"title" => "no title"}, render(HandledReuseResponse))
  end

  def test_recoverable_errors_narrow_what_is_recovered
    with_configuration(recoverable_errors: [Boom]) { assert_equal({"name" => nil}, render(LenientResponse)) }
    with_configuration(recoverable_errors: [ArgumentError]) { assert_raises(Boom) { render(LenientResponse) } }
  end

  def test_changing_config_on_error_recompiles_plans
    klass = define { field :name, type: :string, nullable: true, &FAIL }

    with_configuration(on_error: :raise) do
      assert_raises(Boom) { render(klass) }
      Versponse.configuration.on_error = :nullify

      assert_equal({"name" => nil}, render(klass))
    end
  end

  def test_hook_gets_each_recovered_error
    reports = []
    hook = ->(error, response:, key:, object:) { reports << [error.class, response, key, object.id] }

    with_configuration(on_recovered_error: hook) { render(LenientResponse) }

    assert_equal [[Boom, LenientResponse, "name", "i1"]], reports
  end

  def test_hook_errors_propagate
    with_configuration(on_recovered_error: ->(*, **) { raise ArgumentError, "hook" }) do
      error = assert_raises(ArgumentError) { render(LenientResponse) }

      assert_equal "hook", error.message
    end
  end

  def test_validating_plans_recover_too
    klass = define do
      field :id, type: :string
      field :name, type: :string, nullable: true, on_error: :nullify, &FAIL
    end

    refute_nil klass.versponse.validating_plan(version: "2025-09")
    assert_equal({"id" => "i1", "name" => nil}, render(klass))
  end

  # Every recovery skips the step's check, so it hands the output to the full validation, :omit included
  def test_recoveries_flag_inline_validation
    plan = OmittedSourceResponse.versponse.validating_plan(version: "2025-09")

    refute_nil plan
    assert(Versponse::InlineValidation.run { plan.call(Item.new("i1"), {}) })
  end

  def test_only_an_explicit_association_policy_recovers_a_child_failure
    assert_equal({"id" => "i1", "child" => nil}, render(ExplicitParentResponse))
    assert_raises(Boom) { render(ClassLevelParentResponse) }
  end

  def test_explicit_association_policy_recovers_child_extraction_errors_but_not_other_versponse_errors
    parent = ->(child) { define { reference :child, from: child, map: ".", nullable: true, on_error: :nullify } }

    assert_equal({"child" => nil}, render(parent.call(MissingChildResponse)))
    assert_raises(Versponse::Error) { render(parent.call(VersponseErrorChildResponse)) }
  end

  def test_hook_errors_in_a_child_propagate
    parent = define { reference :child, from: RecoveringChildResponse, map: ".", nullable: true, on_error: :nullify }
    hook = ->(_error, response:, **) { raise ArgumentError, "hook" if response == RecoveringChildResponse }

    with_configuration(on_recovered_error: hook) do
      assert_raises(ArgumentError) { render(parent) }
    end
  end
end
