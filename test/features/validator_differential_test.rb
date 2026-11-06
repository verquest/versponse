# frozen_string_literal: true

require "test_helper"
require "bigdecimal"
require_relative "../support/stora_field_types"

# The compiled checker must agree with json_schemer on rendered examples and on broken copies of them
class ValidatorDifferentialTest < Minitest::Test
  include ConfigurationTestHelper
  include ExampleObjects

  REPLACEMENTS = [nil, 0, 1, 1.0, BigDecimal(1), 1.5, -1, "", "x", "a" * 300, true, [], ["x"], {}, {"x" => 1}].freeze

  # Every json_schema_version, so version-specific rules (integer, $ref siblings) are compared too
  VERSIONS = Versponse::Configuration::SCHEMAS.keys.freeze

  STORA_VALUES = [
    "a@b.co", "nope", "123e4567-e89b-12d3-a456-426614174000", "2025-09-01", "2025-09-01T12:30:00Z", "https://x.io",
    "http://x.io", "site_1", "x\nsite_1", "unit_1", "", 1, nil, {}, {"a" => "b"}, {"a" => 1},
    {"notice_period" => 1}, {"notice_period" => 0}, {"notice_period" => "send_immediately"}, {"notice_period" => nil},
    {"notice_period" => "x"}, (1..21).to_h { |index| ["k#{index}", "v"] }
  ].freeze
  ENUM_VALUES = ["a", "b", "site_1", "site_2", "", 0, 1, 2, 1.0, 1.5, true, false, nil, [], {}, {"a" => 1}].freeze
  UNION_VALUES = [1, 0, 1.0, 1.5, "x", "other", "now", "2025-09-01T12:30:00Z", "send_immediately", nil, true, [], {}].freeze

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
    checker = klass.versponse.checker(version:, view:)
    schemer = klass.versponse.schemer(version:, view:)
    payloads.reject { |payload| checker.valid?(payload) == schemer.valid?(payload) }.map { |payload| [klass.name, view, payload] }
  end

  def test_every_example_compiles
    uncompiled = Versponse::Registry.classes.select { |klass| klass.name&.start_with?("Examples::") }.flat_map do |klass|
      klass.versponse.versions.flat_map { |definition| definition.view_names.map { |view| [klass, definition.name, view] } }
    end.reject { |klass, version, view| klass.versponse.checker(version:, view:) }

    assert_empty uncompiled
  end

  def test_checker_agrees_on_examples_and_mutations
    found = VERSIONS.flat_map do |json_schema_version|
      with_configuration(json_schema_version:) do
        cases.flat_map do |klass, object, options|
          version = options.fetch(:version, "2025-09")
          view = options.fetch(:view, :default)
          rendered = klass.serialize(object, version:, view:, expand: options[:expand])
          disagreements(klass, version, view, [rendered] + mutations(rendered)).map { |found| [json_schema_version, *found] }
        end
      end
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

  def test_checker_agrees_on_type_unions
    klass = Class.new(Versponse::Base) do
      version("2025-09") do
        field :notice_period, type: %i[integer string], nullable: true
        field :starts_at, type: %i[string integer], format: "date-time"
        field :stora_notice_period, type: %i[integer string], nullable: true,
          any_of: [{"type" => "integer"}, {"enum" => ["send_immediately"]}, {"type" => "null"}]
        array :sizes, type: %i[integer string]
      end
    end
    base = {"notice_period" => 1, "starts_at" => 5, "stora_notice_period" => 5, "sizes" => [1]}
    keys = %w[notice_period starts_at stora_notice_period]
    payloads = UNION_VALUES.flat_map { |value| keys.map { |key| base.merge(key => value) } + [base.merge("sizes" => [value])] }

    found = VERSIONS.flat_map do |json_schema_version|
      with_configuration(json_schema_version:) do
        refute_nil klass.versponse.checker(version: "2025-09", view: :default)
        disagreements(klass, "2025-09", :default, payloads)
      end
    end

    assert_empty found
  end

  def test_checker_agrees_on_typed_enums
    found = with_configuration(custom_field_types: STORA_FIELD_TYPES) do
      klass = Class.new(Versponse::Base) do
        version("2025-09") do
          enum :string, type: :string, values: %w[a b]
          enum :nullable_string, type: :string, values: %w[a], nullable: true
          enum :integer, type: :integer, values: [1, 2]
          enum :number, type: :number, values: [1, 1.5]
          enum :boolean, type: :boolean, values: [true]
          enum :object, type: :object, values: [{"a" => 1}]
          enum :union, type: %i[integer string], values: [1, "a"], nullable: true
          enum :custom, type: :site_id, values: %w[site_1]
        end
      end
      base = {"string" => "a", "nullable_string" => nil, "integer" => 1, "number" => 1.5, "boolean" => true,
              "object" => {"a" => 1}, "union" => 1, "custom" => "site_1"}
      payloads = ENUM_VALUES.flat_map { |value| base.keys.map { |key| base.merge(key => value) } }

      refute_nil klass.versponse.checker(version: "2025-09", view: :default)
      disagreements(klass, "2025-09", :default, [base] + payloads)
    end

    assert_empty found
  end
end
