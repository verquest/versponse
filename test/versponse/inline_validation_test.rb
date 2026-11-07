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

  def test_ok_treats_raising_and_deferring_checks_as_failures
    raising = Object.new.tap { |check| def check.valid?(_data) = raise(FloatDomainError) }
    deferring = Object.new.tap { |check| def check.valid?(_data) = throw(Versponse::Validator::Root::DEFER) }

    refute Versponse::InlineValidation.ok?(raising, 1)
    refute Versponse::InlineValidation.ok?(deferring, 1)
  end
end
