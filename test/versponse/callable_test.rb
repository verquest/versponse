# frozen_string_literal: true

require "test_helper"

class Versponse::CallableTest < Minitest::Test
  def test_wraps_one_argument_lambdas
    wrapped = Versponse::Callable.normalize(->(object) { object * 2 })

    assert_equal 4, wrapped.call(2, {})
  end

  def test_keeps_two_argument_lambdas_and_procs
    two_arguments = ->(object, context) { [object, context] }
    one_argument_proc = proc { |object| object }

    assert_same two_arguments, Versponse::Callable.normalize(two_arguments)
    assert_same one_argument_proc, Versponse::Callable.normalize(one_argument_proc)
  end

  def test_keeps_nil
    assert_nil Versponse::Callable.normalize(nil)
  end

  def test_wraps_one_argument_methods
    wrapped = Versponse::Callable.normalize(5.method(:+))

    assert_equal 7, wrapped.call(2, {})
  end

  def test_wraps_lambdas_with_an_optional_argument
    wrapped = Versponse::Callable.normalize(->(object = nil) { object })

    assert_equal 2, wrapped.call(2, {})
  end

  def test_rejects_lambdas_needing_more_than_two_arguments
    assert_raises(Versponse::DefinitionError) { Versponse::Callable.normalize(->(_a, _b, _c, _d = nil) { true }) }
  end

  def test_rejects_required_keyword_arguments
    assert_raises(Versponse::DefinitionError) { Versponse::Callable.normalize(->(_object, context:) { context }) }
  end

  def test_symbol_procs_take_the_object_only
    wrapped = Versponse::Callable.normalize(:upcase.to_proc)

    assert_equal "AB", wrapped.call("ab", {})
  end

  def test_methods_with_unnamed_rest_parameters_take_the_object_only
    wrapped = Versponse::Callable.normalize((+"ab").method(:concat))

    assert_equal "abx", wrapped.call(+"x", {})
  end

  def test_rejects_values_that_are_not_callable
    error = assert_raises(Versponse::DefinitionError) { Versponse::Callable.normalize(:active?) }

    assert_equal "expected a callable (a Proc, lambda or Method), got :active?", error.message
  end

  def test_callable_objects_are_normalized
    one = Class.new { def call(object) = object * 2 }.new
    two = Class.new { def call(object, context) = [object, context] }.new

    assert_equal 4, Versponse::Callable.normalize(one).call(2, {})
    assert_same two, Versponse::Callable.normalize(two)
    assert_raises(Versponse::DefinitionError) { Versponse::Callable.normalize(Class.new { def call(_a, _b, _c) = nil }.new) }
  end

  def test_rejects_other_arities
    assert_raises(Versponse::DefinitionError) { Versponse::Callable.normalize(->(_name, _object, _options) { true }) }
  end
end
