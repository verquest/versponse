# frozen_string_literal: true

require "test_helper"

class Versponse::ErrorPolicyConfigurationTest < Minitest::Test
  include ConfigurationTestHelper

  def setup
    @config = Versponse::Configuration.new
  end

  def test_defaults
    assert_equal :raise, @config.on_error
    assert_equal [StandardError], @config.recoverable_errors
    assert_nil @config.on_recovered_error
  end

  def test_on_error_takes_a_policy_or_a_handler
    %i[raise nullify omit].each do |policy|
      @config.on_error = policy

      assert_equal policy, @config.on_error
    end
    handler = ->(_error, _object, _key, _context) {}
    @config.on_error = handler

    assert_same handler, @config.on_error
  end

  def test_on_error_rejects_anything_else
    error = assert_raises(ArgumentError) { @config.on_error = :ignore }

    assert_equal "on_error must be :raise, :nullify, :omit or a callable taking (error, object, key, context)", error.message
    assert_raises(ArgumentError) { @config.on_error = ->(_error) {} }
  end

  def test_recoverable_errors_takes_standard_error_classes
    @config.recoverable_errors = [ArgumentError, KeyError]

    assert_equal [ArgumentError, KeyError], @config.recoverable_errors
    assert_predicate @config.recoverable_errors, :frozen?
  end

  def test_recoverable_errors_rejects_anything_else
    assert_raises(ArgumentError) { @config.recoverable_errors = ArgumentError }
    assert_raises(ArgumentError) { @config.recoverable_errors = [Exception] }
    assert_raises(ArgumentError) { @config.recoverable_errors = ["ArgumentError"] }
  end

  def test_on_recovered_error_takes_a_callable_or_nil
    hook = ->(_error, **) {}
    @config.on_recovered_error = hook

    assert_same hook, @config.on_recovered_error
    @config.on_recovered_error = nil

    assert_nil @config.on_recovered_error
    assert_raises(ArgumentError) { @config.on_recovered_error = :log }
  end

  def test_on_error_and_recoverable_errors_reset_the_caches
    with_configuration(on_error: :raise, recoverable_errors: [StandardError]) do
      generation = Versponse.cache_generation
      Versponse.configuration.on_error = :nullify
      Versponse.configuration.recoverable_errors = [ArgumentError]

      assert_equal generation + 2, Versponse.cache_generation
    end
  end
end
