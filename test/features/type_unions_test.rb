# frozen_string_literal: true

require "test_helper"
require_relative "../support/stora_field_types"

class TypeUnionsTest < Minitest::Test
  include ConfigurationTestHelper

  class NoticeResponse < Versponse::Base
    version "2025-09" do
      field :notice_period, type: %i[integer string], nullable: true
      field :priority, type: [:integer, "string", :integer]
      array :sizes, type: %i[integer string]
    end
  end

  class StartsResponse < Versponse::Base
    version "2025-09" do
      field :starts_at, type: %i[string integer], format: "date-time", nullable: true
    end
  end

  # Stora's notice_period: the union plus an any_of that narrows strings to one value.
  # nullable: never adds a null branch to any_of, so the null branch is listed here.
  NOTICE_ANY_OF = [{"type" => "integer"}, {"enum" => ["send_immediately"]}, {"type" => "null"}].freeze

  class NotifyResponse < Versponse::Base
    version "2025-09" do
      field :notice_period, type: %i[integer string], nullable: true, any_of: NOTICE_ANY_OF
    end
  end

  def define(&) = Class.new(Versponse::Base, &)

  def render(notice_period: 7, priority: "high", sizes: [1, "L"]) = NoticeResponse.serialize({notice_period:, priority:, sizes:}, version: "2025-09")

  def notify(value) = NotifyResponse.serialize({notice_period: value}, version: "2025-09")

  def test_union_with_any_of_schema
    expected = {"type" => %w[integer string null], "anyOf" => NOTICE_ANY_OF}

    assert_equal expected, NotifyResponse.to_schema(version: "2025-09")["properties"]["notice_period"]
    assert_equal expected, NotifyResponse.to_validation_schema(version: "2025-09")["properties"]["notice_period"]
  end

  def test_union_with_any_of_validates_output
    assert_equal({"notice_period" => 5}, notify(5))
    assert_equal({"notice_period" => "send_immediately"}, notify("send_immediately"))
    assert_equal({"notice_period" => nil}, notify(nil))
    assert_raises(Versponse::InvalidOutputError) { notify("other") }
    assert_raises(Versponse::InvalidOutputError) { notify(1.5) }
  end

  def test_schema
    properties = NoticeResponse.to_schema(version: "2025-09")["properties"]

    assert_equal({"type" => %w[integer string null]}, properties["notice_period"])
    assert_equal({"type" => %w[integer string]}, properties["priority"])
    assert_equal({"type" => "array", "items" => {"type" => %w[integer string]}}, properties["sizes"])
  end

  def test_renders_and_validates_each_type
    assert_equal({"notice_period" => 7, "priority" => "high", "sizes" => [1, "L"]}, render)
    assert_equal({"notice_period" => "send_immediately", "priority" => 1, "sizes" => []}, render(notice_period: "send_immediately", priority: 1, sizes: []))
    assert_nil render(notice_period: nil)["notice_period"]
    assert_raises(Versponse::InvalidOutputError) { render(notice_period: true) }
    assert_raises(Versponse::InvalidOutputError) { render(priority: nil) }
    assert_raises(Versponse::InvalidOutputError) { render(sizes: [1.5]) }
  end

  def test_definition_errors
    error = with_configuration(custom_field_types: STORA_FIELD_TYPES) do
      assert_raises(Versponse::DefinitionError) { define { version("2025-09") { field :id, type: %i[site_id string] } } }
    end

    assert_equal "id: type unions take only built-in types (string, number, integer, boolean, object), not site_id", error.message
    assert_raises(Versponse::DefinitionError) { define { version("2025-09") { field :x, type: %i[integer text] } } }
    assert_raises(Versponse::DefinitionError) { define { version("2025-09") { field :x, type: %i[integer integer] } } }
    assert_raises(Versponse::DefinitionError) { define { version("2025-09") { array :x, type: %i[null string] } } }
  end

  def test_openapi30_documents_use_any_of
    union = {"anyOf" => [{"type" => "integer"}, {"type" => "string"}]}

    with_configuration(json_schema_version: :openapi30) do
      properties = NoticeResponse.to_schema(version: "2025-09")["properties"]

      assert_equal union.merge("nullable" => true), properties["notice_period"]
      assert_equal union, properties["priority"]
      assert_equal({"type" => "array", "items" => union}, properties["sizes"])
      assert_equal({"type" => %w[integer string null]}, NoticeResponse.to_validation_schema(version: "2025-09")["properties"]["notice_period"])
    end
  end

  def test_openapi30_output_validation
    with_configuration(json_schema_version: :openapi30) do
      assert_nil render(notice_period: nil)["notice_period"]
      assert_raises(Versponse::InvalidOutputError) { render(notice_period: true) }
    end
  end

  def test_openapi30_union_with_any_of_uses_all_of
    expected = {"allOf" => [{"anyOf" => [{"type" => "integer"}, {"type" => "string"}]}, {"anyOf" => NOTICE_ANY_OF}], "nullable" => true}

    with_configuration(json_schema_version: :openapi30) do
      assert_equal expected, NotifyResponse.to_schema(version: "2025-09")["properties"]["notice_period"]
      assert_equal({"type" => %w[integer string null], "anyOf" => NOTICE_ANY_OF}, NotifyResponse.to_validation_schema(version: "2025-09")["properties"]["notice_period"])
      assert_equal({"notice_period" => nil}, notify(nil))
      assert_equal({"notice_period" => "send_immediately"}, notify("send_immediately"))
      assert_raises(Versponse::InvalidOutputError) { notify("other") }
    end
  end

  def test_format_and_formatter_apply_to_unions
    assert_equal({"type" => %w[string integer null], "format" => "date-time"}, StartsResponse.to_schema(version: "2025-09")["properties"]["starts_at"])
    assert_equal({"starts_at" => "2025-09-01T10:00:00.000Z"}, StartsResponse.serialize({starts_at: Time.new(2025, 9, 1, 12, 0, 0, "+02:00")}, version: "2025-09"))
    assert_equal({"starts_at" => 5}, StartsResponse.serialize({starts_at: 5}, version: "2025-09"))
  end

  def test_openapi30_array_union_with_item_any_of_uses_all_of
    klass = define { version("2025-09") { array :sizes, type: %i[integer string], item_schema_options: {any_of: [{"type" => "integer"}, {"enum" => ["L"]}]} } }
    union = {"anyOf" => [{"type" => "integer"}, {"type" => "string"}]}
    narrowed = {"anyOf" => [{"type" => "integer"}, {"enum" => ["L"]}]}

    assert_equal({"type" => %w[integer string]}.merge(narrowed), klass.to_schema(version: "2025-09")["properties"]["sizes"]["items"])
    with_configuration(json_schema_version: :openapi30) do
      assert_equal({"allOf" => [union, narrowed]}, klass.to_schema(version: "2025-09")["properties"]["sizes"]["items"])
      assert_equal({"sizes" => [1, "L"]}, klass.serialize({sizes: [1, "L"]}, version: "2025-09"))
      assert_raises(Versponse::InvalidOutputError) { klass.serialize({sizes: ["M"]}, version: "2025-09") }
    end
  end

  def test_unions_in_with_options
    klass = define do
      version("2025-09") do
        with_options(type: %i[integer string], nullable: true) do
          field :notice_period
          array :sizes
        end
      end
    end
    properties = klass.to_schema(version: "2025-09")["properties"]

    assert_equal({"type" => %w[integer string null]}, properties["notice_period"])
    assert_equal({"type" => %w[array null], "items" => {"type" => %w[integer string]}}, properties["sizes"])
    assert_equal({"notice_period" => "x", "sizes" => [1, "L"]}, klass.serialize({notice_period: "x", sizes: [1, "L"]}, version: "2025-09"))
  end

  def test_union_with_enum
    klass = define { version("2025-09") { field :notice_period, type: %i[integer string], nullable: true, enum: [7, "send_immediately", nil] } }
    notice = ->(value) { klass.serialize({notice_period: value}, version: "2025-09") }

    assert_equal({"type" => %w[integer string null], "enum" => [7, "send_immediately", nil]}, klass.to_schema(version: "2025-09")["properties"]["notice_period"])
    assert_equal({"notice_period" => 7}, notice.call(7))
    assert_equal({"notice_period" => nil}, notice.call(nil))
    assert_raises(Versponse::InvalidOutputError) { notice.call(8) }
    with_configuration(json_schema_version: :openapi30) do
      assert_equal({"anyOf" => [{"type" => "integer"}, {"type" => "string"}], "enum" => [7, "send_immediately", nil], "nullable" => true}, klass.to_schema(version: "2025-09")["properties"]["notice_period"])
    end
  end
end
