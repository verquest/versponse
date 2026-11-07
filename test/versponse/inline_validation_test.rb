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
      step = Versponse::Steps::Read.new(key: "a", name: :a).checked(check)

      assert(Versponse::InlineValidation.run { step.call({a: 1}, true, {}, {}, Versponse::Expansion::NONE) })
    end
  end

  # A String view finds the same cached validating plan as its Symbol, instead of rebuilding it per render
  def test_validating_plans_are_cached_for_string_views
    klass = Class.new(Versponse::Base) { version("2025-09") { field :a, type: :string } }

    assert_same klass.versponse.validating_plan(version: "2025-09", view: :default), klass.versponse.validating_plan(version: "2025-09", view: "default")
  end
end
