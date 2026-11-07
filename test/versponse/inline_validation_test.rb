# frozen_string_literal: true

require "test_helper"

class Versponse::InlineValidationTest < Minitest::Test
  def test_run_reports_failures_and_isolates_nested_runs
    inner = nil
    outer = Versponse::InlineValidation.run do
      Versponse::InlineValidation.failed!
      inner = Versponse::InlineValidation.run { nil }
    end

    assert outer
    refute inner
    refute Versponse::InlineValidation.run { Versponse::InlineValidation.run { Versponse::InlineValidation.failed! } }
  end

  def test_rechecks_run_after_the_render_and_stay_in_their_run
    check = Versponse::Validator::ClassCheck.new(Array)
    value = []
    failed = Versponse::InlineValidation.run do
      Versponse::InlineValidation.recheck_later(check, value)

      refute Versponse::InlineValidation.run { nil }
    end

    refute failed
    assert(Versponse::InlineValidation.run { Versponse::InlineValidation.recheck_later(Versponse::Validator::ClassCheck.new(Hash), value) })
  end

  def test_run_restores_the_flag_after_an_exception
    Versponse::InlineValidation.run do
      Versponse::InlineValidation.failed!
      assert_raises(RuntimeError) { Versponse::InlineValidation.run { raise "boom" } }

      assert Thread.current[Versponse::InlineValidation::FLAG]
    end

    assert_nil Thread.current[Versponse::InlineValidation::FLAG]
  end

  def test_checks_that_raise_or_defer_count_as_failures
    raising = Object.new.tap { |check| def check.valid?(_data) = raise(FloatDomainError) }
    deferring = Object.new.tap { |check| def check.valid?(_data) = throw(Versponse::Validator::Root::DEFER) }

    [raising, deferring].each do |check|
      step = Versponse::Steps::Read.new(key: "a", name: :a).checked(check, recheck: false)

      assert(Versponse::InlineValidation.run { step.call({a: 1}, true, {}, {}, Versponse::Expansion::NONE) })
    end
  end

  # A String view finds the same cached validating plan as its Symbol, instead of rebuilding it per render
  def test_validating_plans_are_cached_for_string_views
    klass = Class.new(Versponse::Base) { version("2025-09") { field :a, type: :string } }

    assert_same klass.versponse.validating_plan(version: "2025-09", view: :default), klass.versponse.validating_plan(version: "2025-09", view: "default")
  end

  # Image URLs built as Symbol-keyed Hashes (stora's images) pass inline, without the full validator
  def test_symbol_keyed_hashes_pass_inline
    klass = Class.new(Versponse::Base) do
      version "2025-09" do
        field :images, type: :object, additional_properties: false,
          properties: {"photo" => {"type" => ["object", "null"], "additionalProperties" => false, "properties" => {"original" => {"type" => "string"}}}}
      end
    end
    plan = klass.versponse.validating_plan(version: "2025-09")

    refute_nil plan
    refute Versponse::InlineValidation.run { plan.call({images: {photo: {original: "https://x"}}}, {}) }
    assert Versponse::InlineValidation.run { plan.call({images: {photo: {original: 1}}}, {}) }
  end
end
