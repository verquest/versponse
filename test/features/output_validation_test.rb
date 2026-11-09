# frozen_string_literal: true

require "test_helper"

class OutputValidationTest < Minitest::Test
  include ConfigurationTestHelper

  class StrictResponse < Versponse::Base
    version "2025-09" do
      field :id, type: :string
      field :count, type: :integer
    end
  end

  def test_raises_with_pointers
    with_configuration(validate_output: true) do
      error = assert_raises(Versponse::InvalidOutputError) { StrictResponse.serialize({id: "a", count: "many"}, version: "2025-09") }

      assert_equal "/count", error.errors.first[:pointer]
      assert_equal "integer", error.errors.first[:type]
      assert_equal "OutputValidationTest::StrictResponse output does not match its 2025-09/default schema: value at `/count` is not an integer", error.message
    end
  end

  def test_points_into_collections
    with_configuration(validate_output: true) do
      error = assert_raises(Versponse::InvalidOutputError) do
        StrictResponse.serialize([{id: "a", count: 1}, {id: "b", count: "x"}], version: "2025-09")
      end

      assert_equal "/1/count", error.errors.first[:pointer]
    end
  end

  def test_off
    with_configuration(validate_output: false) do
      assert_equal "many", StrictResponse.serialize({id: "a", count: "many"}, version: "2025-09")["count"]
    end
  end

  # Checkers are cached per version and view; an unsupported schema's nil is cached too, so it compiles once
  def test_checkers_compile_once
    klass = Class.new(Versponse::Base) { version("2025-09") { field :code, type: :string, content_encoding: "base64" } }
    compiler = Versponse::Validator::Compiler.singleton_class
    calls = 0
    compiler.alias_method(:original_call, :call)
    compiler.define_method(:call) { |*args| (calls += 1) && original_call(*args) }

    2.times { assert_nil klass.versponse.checker(version: "2025-09") }

    assert_equal 1, calls
  ensure
    compiler.alias_method(:call, :original_call)
    compiler.remove_method(:original_call)
  end

  INVALID = {id: "a", count: "many"}.freeze

  def test_validate_output_callable_decides_per_render_with_the_class
    received = []
    with_configuration(validate_output: ->(klass) { received << klass and klass == StrictResponse }) do
      assert_raises(Versponse::InvalidOutputError) { StrictResponse.serialize(INVALID, version: "2025-09") }
      Class.new(Versponse::Base) { version("2025-09") { field :count, type: :integer } }.then do |other|
        assert_equal "many", other.serialize({count: "many"}, version: "2025-09")["count"]
        assert_equal [StrictResponse, other], received
      end
    end
  end

  def test_sample_rate_zero_never_validates_and_skips_the_callable
    called = false
    callable = ->(_klass) { called = true }

    with_configuration(validate_output: callable, validate_output_sample_rate: 0) do
      assert_equal "many", StrictResponse.serialize(INVALID, version: "2025-09")["count"]
    end

    refute called
  end

  def test_sample_rate_applies_on_top_of_validate_output
    with_configuration(validate_output: true, validate_output_sample_rate: 1) do
      assert_raises(Versponse::InvalidOutputError) { StrictResponse.serialize(INVALID, version: "2025-09") }
    end
    with_configuration(validate_output: false, validate_output_sample_rate: 1) do
      assert_equal "many", StrictResponse.serialize(INVALID, version: "2025-09")["count"]
    end
  end

  def test_sampling_draws_per_render
    with_configuration(validate_output: true, validate_output_sample_rate: 0.5) do
      outcomes = Array.new(40) do
        StrictResponse.serialize(INVALID, version: "2025-09")
        :skipped
      rescue Versponse::InvalidOutputError
        :validated
      end

      assert_equal %i[skipped validated], outcomes.uniq.sort
    end
  end

  class MapResponse < Versponse::Base
    version("2025-09") { field :data, type: :object }
  end

  # Symbol keys make the inline check defer; json_schemer then reads them as Strings and accepts the output
  def test_inline_failures_that_json_schemer_accepts_return_the_output
    with_configuration(validate_output: true) do
      assert_equal({"data" => {a: 1}}, MapResponse.serialize({data: {a: 1}}, version: "2025-09"))
    end
  end

  def test_validated_renders_use_the_validating_plan
    with_configuration(validate_output: true) do
      refute_nil StrictResponse.versponse.validating_plan(version: "2025-09")
      assert_equal({"id" => "a", "count" => 1}, StrictResponse.serialize({id: "a", count: 1}, version: "2025-09"))
    end
  end

  class MutatingResponse < Versponse::Base
    version "2025-09" do
      array :tags, type: :string, min_items: 1
      field(:first, type: :string) { |object| object[:tags].shift }
      field :meta, type: :object, additional_properties: {type: "string"}
      field(:touched, type: :boolean) { |object| object[:meta].store("count", 1) && true }
    end
  end

  # Unfrozen Hashes passed through from the source are checked again after the render, so changing them in place later is caught
  def test_values_changed_later_in_the_render_are_caught
    with_configuration(validate_output: true) do
      refute_nil MutatingResponse.versponse.validating_plan(version: "2025-09")
      error = assert_raises(Versponse::InvalidOutputError) { MutatingResponse.serialize({tags: ["a"], meta: {}}, version: "2025-09") }

      assert_equal %w[/meta/count], error.errors.map { |item| item[:pointer] }.sort
    end
  end

  class FrozenMetaResponse < Versponse::Base
    version "2025-09" do
      field :meta, type: :object, additional_properties: {type: "array", items: {type: "string"}}
      field(:later, type: :boolean) { |object| object[:meta]["k"] << 1 && true }
    end
  end

  # frozen? is shallow: a frozen Hash whose Array is changed later is still caught
  def test_frozen_containers_changed_later_are_caught
    with_configuration(validate_output: true) do
      error = assert_raises(Versponse::InvalidOutputError) { FrozenMetaResponse.serialize({meta: {"k" => ["a"]}.freeze}, version: "2025-09") }

      assert_equal ["/meta/k/1"], error.errors.map { |item| item[:pointer] }
    end
  end

  class ShortNameResponse < Versponse::Base
    version "2025-09" do
      field :name, type: :string, max_length: 3
      field(:later, type: :boolean) { |object| object[:name] << "toolong" && true }
    end
  end

  # A String whose schema limits more than its type is checked after the render, so growing it in place is caught
  def test_constrained_strings_changed_later_are_caught
    with_configuration(validate_output: true) do
      error = assert_raises(Versponse::InvalidOutputError) { ShortNameResponse.serialize({name: +"abc"}, version: "2025-09") }

      assert_equal ["/name"], error.errors.map { |item| item[:pointer] }
    end
  end

  # A Numeric whose value can change in place; json_schemer's integer check reads the value (floor == self)
  class Amount < Numeric
    attr_accessor :value

    def initialize(value) = (@value = value)
    def floor = value.floor
    def ==(other) = value == (other.is_a?(Amount) ? other.value : other)
  end

  class AmountResponse < Versponse::Base
    version "2025-09" do
      field :amount, type: :integer
      field(:later, type: :boolean) { |object| (object[:amount].value = 1.5) && true }
    end
  end

  def test_integers_changed_later_are_caught
    with_configuration(validate_output: true) do
      assert_raises(Versponse::InvalidOutputError) { AmountResponse.serialize({amount: Amount.new(1)}, version: "2025-09") }
    end
  end

  class ItemResponse < Versponse::Base
    version("2025-09") { field :meta, type: :object, additional_properties: {type: "string"} }
  end

  class EitherResponse < Versponse::Base
    version "2025-09" do
      one_of(:either) { reference from: ItemResponse, match: Hash }
      field(:later, type: :boolean) { |object| object[:either][:meta].store("count", 1) && true }
    end
  end

  # A one_of is checked as a whole after it renders; its rendered Hash still holds the source's Hash
  def test_subtrees_changed_later_in_the_render_are_caught
    with_configuration(validate_output: true) do
      assert_raises(Versponse::InvalidOutputError) { EitherResponse.serialize({either: {meta: {}}}, version: "2025-09") }
    end
  end

  def test_the_suite_runs_with_validation_on
    assert Versponse.configuration.validate_output
  end

  class NullableResponse < Versponse::Base
    version "2025-09" do
      reference :strict, from: StrictResponse, nullable: true
      enum :status, type: :string, values: %w[on off], nullable: true
      one_of :either, nullable: true do
        reference from: StrictResponse, match: Hash
      end
    end
  end

  def test_openapi30_accepts_nil_for_nullable_references_enums_and_one_of
    with_configuration(json_schema_version: :openapi30, validate_output: true) do
      assert_equal({"strict" => nil, "status" => nil, "either" => nil}, NullableResponse.serialize({strict: nil, status: nil, either: nil}, version: "2025-09"))
    end
  end

  class NodeResponse < Versponse::Base
    version "2025-09" do
      field :name, type: :string
      collection :children, item: NodeResponse
    end
  end

  def test_openapi30_validates_recursive_output
    with_configuration(json_schema_version: :openapi30, validate_output: true) do
      tree = {name: "Root", children: [{name: "Leaf", children: []}]}

      assert_equal "Leaf", NodeResponse.serialize(tree, version: "2025-09")["children"].first["name"]
    end
  end

  def test_json_schemer_decides_when_the_checker_rejects
    StrictResponse.stubs(:checker).returns(Versponse::Validator::Constant::INVALID)

    with_configuration(validate_output: true) do
      assert_equal "a", StrictResponse.serialize({id: "a", count: 1}, version: "2025-09")["id"]
      assert_raises(Versponse::InvalidOutputError) { StrictResponse.serialize({id: "a", count: "many"}, version: "2025-09") }
    end
  end

  def test_uncompiled_schemas_validate_with_json_schemer
    klass = Class.new(Versponse::Base) { version("2025-09") { field :code, type: :string, content_encoding: "base64" } }

    with_configuration(validate_output: true) do
      assert_nil klass.versponse.checker(version: "2025-09")
      assert_raises(Versponse::InvalidOutputError) { klass.serialize({code: 1}, version: "2025-09") }
    end
  end

  def test_anonymous_classes_are_named_in_errors
    klass = Class.new(Versponse::Base) { version("2025-09") { field :a, type: :integer } }

    with_configuration(validate_output: true) do
      error = assert_raises(Versponse::InvalidOutputError) { klass.serialize({a: "x"}, version: "2025-09") }

      assert_match(/\AAnonymousResponse output/, error.message)
    end
  end

  class CodeResponse < Versponse::Base
    version("2025-09") { field :code, type: :string, pattern: /\A[a-z]+\z/ }
  end

  # Patterns are ECMA-262, where ^ and $ anchor the whole string, not a line
  def test_patterns_anchor_the_whole_string
    with_configuration(validate_output: true) do
      assert_equal({"code" => "abc"}, CodeResponse.serialize({code: "abc"}, version: "2025-09"))
      assert_raises(Versponse::InvalidOutputError) { CodeResponse.serialize({code: "abc\nDEF"}, version: "2025-09") }
    end
  end

  # Items are validated one by one, so their messages are rewritten to point into the collection
  def test_message_names_the_first_two_errors
    with_configuration(validate_output: true) do
      error = assert_raises(Versponse::InvalidOutputError) do
        StrictResponse.serialize([{id: 1, count: "x"}, {id: 2, count: "y"}], version: "2025-09")
      end

      assert_equal "OutputValidationTest::StrictResponse output does not match its 2025-09/default schema: " \
        "value at `/0/id` is not a string; value at `/0/count` is not an integer; and 2 more", error.message
      assert_equal "value at `/1/count` is not an integer", error.errors.last[:message]
    end
  end
end
