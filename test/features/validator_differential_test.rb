# frozen_string_literal: true

require "test_helper"
require_relative "../support/stora_field_types"

# The compiled checker must agree with json_schemer on rendered examples and on broken copies of them
class ValidatorDifferentialTest < Minitest::Test
  include ConfigurationTestHelper
  include ExampleObjects

  REPLACEMENTS = [nil, 0, 1, 1.5, -1, "", "x", "a" * 300, true, [], ["x"], {}, {"x" => 1}].freeze

  STORA_VALUES = [
    "a@b.co", "nope", "123e4567-e89b-12d3-a456-426614174000", "2025-09-01", "2025-09-01T12:30:00Z", "https://x.io",
    "http://x.io", "site_1", "x\nsite_1", "unit_1", "", 1, nil, {}, {"a" => "b"}, {"a" => 1},
    {"notice_period" => 1}, {"notice_period" => 0}, {"notice_period" => "send_immediately"}, {"notice_period" => nil},
    {"notice_period" => "x"}, (1..21).to_h { |index| ["k#{index}", "v"] }
  ].freeze

  def cases
    [
      [Examples::UnitTypeResponse, unit_type, {}],
      [Examples::UnitTypeResponse, unit_type, {expand: ["*"]}],
      [Examples::UnitTypeResponse, unit_type, {view: :embedded_without_prices}],
      [Examples::UnitTypeResponse, unit_type, {version: "2026-03", view: :embedded}],
      [Examples::OrderResponse, order_with_tenancy, {}],
      [Examples::OrderResponse, order_with_tenancy, {expand: Examples::OrderResponse.expandable_paths(version: "2025-09")}],
      [Examples::TaskResponse, task, {}],
      [Examples::TaskResponse, task, {expand: ["resource"]}],
      [Examples::CategoryResponse, category_tree, {}],
      [Examples::ActivityFeedResponse, feed, {}]
    ]
  end

  # Every copy of value with one change: a key removed, an extra key, or one value replaced
  def mutations(value)
    case value
    when Hash then hash_mutations(value) + REPLACEMENTS
    when Array then array_mutations(value) + REPLACEMENTS
    else REPLACEMENTS
    end
  end

  def hash_mutations(hash)
    hash.each_key.flat_map { |key| [hash.except(key)] + mutations(hash[key]).map { |mutated| hash.merge(key => mutated) } } +
      [hash.merge("zz_extra" => 1)]
  end

  def array_mutations(array)
    array.each_index.flat_map { |index| mutations(array[index]).map { |mutated| array.dup.tap { |copy| copy[index] = mutated } } }
  end

  def disagreements(klass, version, view, payloads)
    checker = klass.checker(version:, view:)
    schemer = klass.schemer(version:, view:)
    payloads.reject { |payload| checker.valid?(payload) == schemer.valid?(payload) }.map { |payload| [klass.name, view, payload] }
  end

  def test_every_example_compiles
    uncompiled = Versponse::Registry.classes.select { |klass| klass.name&.start_with?("Examples::") }.flat_map do |klass|
      klass.versions.flat_map { |definition| definition.view_names.map { |view| [klass, definition.name, view] } }
    end.reject { |klass, version, view| klass.checker(version:, view:) }

    assert_empty uncompiled
  end

  def test_checker_agrees_on_examples_and_mutations
    found = cases.flat_map do |klass, object, options|
      version = options.fetch(:version, "2025-09")
      view = options.fetch(:view, :default)
      rendered = klass.serialize(object, version:, view:, expand: options[:expand])
      disagreements(klass, version, view, [rendered] + mutations(rendered))
    end

    assert_empty found
  end

  def test_checker_agrees_on_stora_custom_types
    found = with_configuration(custom_field_types: STORA_FIELD_TYPES) do
      STORA_FIELD_TYPES.each_key.flat_map do |type|
        klass = Class.new(Versponse::Base) { version("2025-09") { field :value, type: } }
        disagreements(klass, "2025-09", :default, STORA_VALUES.map { |value| {"value" => value} })
      end
    end

    assert_empty found
  end
end
