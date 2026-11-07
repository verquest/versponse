# frozen_string_literal: true

require "test_helper"
require "bigdecimal"
require "json_schemer"

# Validating plans check while rendering; their verdict must match json_schemer on the finished output, for valid
# inputs and for inputs with one leaf replaced, and their output must equal the plain render
class InlineValidationDifferentialTest < Minitest::Test
  include ConfigurationTestHelper
  include ExampleObjects

  REPLACEMENTS = [nil, 0, 1, 1.0, BigDecimal(1), 1.5, -1, "", "x", "a" * 300, true, [], ["x"], {}, {"x" => 1}, {x: 1}].freeze
  VERSIONS = Versponse::Configuration::SCHEMAS.keys.freeze

  class ChildResponse < Versponse::Base
    version "2025-09" do
      identifier :id
      field :rank, type: :integer, nullable: true
    end
  end

  class TreeResponse < Versponse::Base
    version "2025-09" do
      field :name, type: :string
      collection :children, item: TreeResponse
    end
  end

  class LeafyResponse < Versponse::Base
    version "2025-09" do
      field :text, type: :string
      field :count, type: :integer
      field :ratio, type: :number
      field :flag, type: :boolean
      field :maybe, type: :string, nullable: true
      field :at, type: :string, format: "date-time"
      field :on, type: :string, format: "date"
      field :mail, type: :string, format: "email"
      field :short, type: :string, max_length: 3
      field :map, type: :object
      field :union, type: %i[integer string], nullable: true
      field :mapped, type: :string, map: "text"
      field(:computed, type: :integer) { |object| object[:count] }
      field :sometimes, type: :string, if: ->(object) { object[:show] }
      enum :choice, type: :string, values: %w[a b]
      const :kind, value: "leafy"
      reference :child, from: ChildResponse
      reference :maybe_child, from: ChildResponse, nullable: true
      reference :described_child, from: ChildResponse, description: "A child"
      reference :expandable_child, from: ChildResponse, expandable: true
      collection :children, item: ChildResponse
      collection :maybe_children, item: ChildResponse, nullable: true
      reference :tree, from: TreeResponse
      object :inline do
        field :x, type: :string
      end
      collection :inline_items do
        field :y, type: :integer
      end
      one_of :either, nullable: true do
        reference from: ChildResponse, match: Hash
      end
    end
  end

  def child = {id: "c1", rank: 1}

  def input
    {
      text: "t", count: 1, ratio: 1.5, flag: true, maybe: nil, at: Time.utc(2025, 9, 1, 10), on: Date.new(2025, 9, 1),
      mail: "a@b.co", short: "abc", map: {"k" => "v"}, union: 5, choice: "a", show: true, sometimes: "s",
      child:, maybe_child: nil, described_child: child, expandable_child: child, children: [child], maybe_children: nil,
      tree: {name: "root", children: [{name: "leaf", children: []}]}, inline: {x: "x"}, inline_items: [{y: 1}], either: child
    }
  end

  # The input with one leaf replaced, at the top level and in nested Hashes
  def mutations(hash)
    hash.flat_map do |key, value|
      replaced = REPLACEMENTS.map { |replacement| hash.merge(key => replacement) }
      nested = value.is_a?(Hash) ? mutations(value).map { |mutated| hash.merge(key => mutated) } : []
      items = (value.is_a?(Array) && value.first.is_a?(Hash)) ? mutations(value.first).map { |mutated| hash.merge(key => [mutated]) } : []
      replaced + nested + items
    end
  end

  def deferred?(value)
    case value
    when Hash then !value.each_key.all?(String) || value.each_value.any? { |item| deferred?(item) }
    when Array then value.any? { |item| deferred?(item) }
    else false
    end
  end

  # [input, problem] pairs where the validating plan disagrees with json_schemer or renders differently
  def disagreements(klass, inputs, expand: nil, view: :default)
    internals = klass.versponse
    plan = internals.plan(version: "2025-09", view:)
    inline = internals.validating_plan(version: "2025-09", view:)
    schemer = internals.schemer(version: "2025-09", view:)
    expansion = internals.expansion(expand, version: "2025-09", view:)
    return [[:no_validating_plan]] unless inline

    inputs.filter_map do |source|
      expected = begin
        plan.call(source, {}.freeze, expansion)
      rescue Versponse::ExtractionError
        next
      end
      output = nil
      failed = Versponse::InlineValidation.run { output = inline.call(source, {}.freeze, expansion) }
      @compared += 1
      valid = begin
        schemer.valid?(expected)
      rescue
        next [source, :inline_accepted_what_json_schemer_cant_decide] unless failed
        next
      end
      next [source, :output_differs] unless output == expected
      next [source, :false_accept] if !failed && !valid
      next [source, :false_reject] if failed && valid && !deferred?(expected)
    end
  end

  def test_inline_validation_agrees_with_json_schemer
    @compared = 0
    found = VERSIONS.flat_map do |json_schema_version|
      with_configuration(json_schema_version:) do
        inputs = [input, input.merge(show: false)] + mutations(input)
        [nil, ["expandable_child"]].flat_map do |expand|
          disagreements(LeafyResponse, inputs, expand:).map { |found| [json_schema_version, expand, *found] }
        end
      end
    end

    assert_empty found.first(5)
    assert_operator @compared, :>, 6000, "most mutated inputs must render, or the comparison is empty"
  end

  def test_validating_plans_prove_the_example_classes
    found = with_configuration(validate_output: true) do
      ValidatorDifferentialTest.new("x").cases.filter_map do |klass, object, options|
        version = options.fetch(:version, "2025-09")
        view = options.fetch(:view, :default)
        inline = klass.versponse.validating_plan(version:, view:)
        next unless inline

        expansion = klass.versponse.expansion(options[:expand], version:, view:)
        output = nil
        failed = Versponse::InlineValidation.run { output = inline.call(object, {}.freeze, expansion) }
        [klass, view, :failed] if failed || output != klass.versponse.plan(version:, view:).call(object, {}.freeze, expansion)
      end
    end

    assert_empty found
  end
end
