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

  def test_accepts_checks_the_arity_of_lambdas_and_methods
    assert Versponse::Callable.accepts?(->(_object, _key, _context) {}, 3)
    assert Versponse::Callable.accepts?(->(*) {}, 4)
    assert Versponse::Callable.accepts?(5.method(:+), 1)
    refute Versponse::Callable.accepts?(->(_object) {}, 3)
    refute Versponse::Callable.accepts?(->(_object, key:) {}, 1)
    refute Versponse::Callable.accepts?(:fill, 3)
  end

  def test_accepts_takes_procs_as_they_are
    assert Versponse::Callable.accepts?(proc { |object| object }, 4)
  end

  # Objects are checked by their call method, like lambdas; one answered by method_missing takes anything
  def test_accepts_checks_the_arity_of_callable_objects
    assert Versponse::Callable.accepts?(Class.new { def call(_object) = nil }.new, 1)
    assert Versponse::Callable.accepts?(Class.new { def call(*) = nil }.new, 3)
    refute Versponse::Callable.accepts?(Class.new { def call = nil }.new, 1)
    refute Versponse::Callable.accepts?(Class.new { def call(_object) = nil }.new, 3)

    dynamic = Class.new do
      def respond_to_missing?(name, include_private = false) = name == :call || super
      def method_missing(name, *args) = (name == :call) ? args : super
    end

    assert Versponse::Callable.accepts?(dynamic.new, 4)

    claimed = Class.new { def respond_to?(name, include_all = false) = name == :call || super }

    assert Versponse::Callable.accepts?(claimed.new, 4)
  end

  # An object with its own #method (a Struct member, a request) is still read through Kernel#method
  def test_callable_objects_with_their_own_method
    with_method = Struct.new(:method) { def call(_object) = nil }.new("GET")

    assert Versponse::Callable.accepts?(with_method, 1)
    refute Versponse::Callable.accepts?(with_method, 3)
    assert_respond_to Versponse::Callable.normalize(with_method), :call
  end
end
