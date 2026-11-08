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

  # A checker that counts its calls
  def counting(answer = true)
    Object.new.tap do |check|
      check.instance_variable_set(:@calls, 0)
      check.define_singleton_method(:valid?) { |_value| (@calls += 1) && answer }
      check.define_singleton_method(:calls) { @calls }
    end
  end

  def test_rechecks_run_after_the_render_and_stay_in_their_run
    check = Versponse::Validator::ClassCheck.new(Array)
    value = []
    failed = Versponse::InlineValidation.run do
      Versponse::InlineValidation.check(check, value, true)

      refute Versponse::InlineValidation.run { nil }
    end

    refute failed
    assert(Versponse::InlineValidation.run { Versponse::InlineValidation.check(Versponse::Validator::ClassCheck.new(Hash), value, true) })
  end

  # A value that is rechecked is checked once, after the render; one frozen all the way down is checked at once
  def test_values_are_checked_once
    check = counting
    Versponse::InlineValidation.run do
      Versponse::InlineValidation.check(check, ["a"], true)

      assert_equal 0, check.calls
    end

    assert_equal 1, check.calls
    Versponse::InlineValidation.run do
      Versponse::InlineValidation.check(check, ["a"].freeze, true)
      Versponse::InlineValidation.check(check, +"a", false)

      assert_equal 3, check.calls
    end

    assert_equal 3, check.calls
  end

  # frozen? is shallow: a frozen container with unfrozen contents can still change
  def test_frozen_containers_with_unfrozen_contents_are_rechecked
    check = counting
    Versponse::InlineValidation.run do
      Versponse::InlineValidation.check(check, {"k" => ["a"]}.freeze, true)
      Versponse::InlineValidation.check(check, [+"a"].freeze, true)

      assert_equal 0, check.calls
    end

    assert_equal 2, check.calls
  end

  def test_failed_checks_set_the_flag
    assert(Versponse::InlineValidation.run { Versponse::InlineValidation.check(counting(false), 1, false) })
    assert(Versponse::InlineValidation.run { Versponse::InlineValidation.check(counting(false), [], true) })
  end

  def test_failures_outside_a_run_leave_no_flag
    Versponse::InlineValidation.failed!

    refute_predicate Versponse::InlineValidation, :failed?
  end

  def test_run_restores_the_flag_after_an_exception
    Versponse::InlineValidation.run do
      Versponse::InlineValidation.failed!
      assert_raises(RuntimeError) { Versponse::InlineValidation.run { raise "boom" } }

      assert_predicate Versponse::InlineValidation, :failed?
    end

    refute_predicate Versponse::InlineValidation, :failed?
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

  # The validating plan's compiler also gives the checker, so the schema is compiled once
  def test_the_schema_is_compiled_once
    klass = Class.new(Versponse::Base) { version("2025-09") { field :a, type: :string } }
    compilers = -> { ObjectSpace.each_object(Versponse::Validator::Compiler).count }
    GC.disable
    before = compilers.call
    klass.versponse.validating_plan(version: "2025-09")

    refute_nil klass.versponse.checker(version: "2025-09")
    assert_equal 1, compilers.call - before
  ensure
    GC.enable
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
