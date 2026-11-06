# frozen_string_literal: true

require "test_helper"
require_relative "../support/stora_field_types"

class CustomFieldTypesTest < Minitest::Test
  include ConfigurationTestHelper

  def with_types(&) = with_configuration(custom_field_types: STORA_FIELD_TYPES, &)

  def define(&) = Class.new(Versponse::Base) { version("2025-09", &) }

  def properties(klass) = klass.to_schema(version: "2025-09")["properties"]

  def test_field_schemas
    with_types do
      klass = define do
        field :id, type: :site_id
        field :email, type: :email, description: "Contact email"
        field :metadata, type: :metadata
      end

      assert_equal({"type" => "string", "pattern" => "^site_"}, properties(klass)["id"])
      assert_equal({"type" => "string", "format" => "email", "description" => "Contact email"}, properties(klass)["email"])
      assert_equal({"type" => "object", "additionalProperties" => {"type" => "string"}, "maxProperties" => 20}, properties(klass)["metadata"])
    end
  end

  def test_field_options_win
    with_types do
      klass = define { field :site, type: :site_id, pattern: "^site_[a-z]+$" }

      assert_equal "^site_[a-z]+$", properties(klass)["site"]["pattern"]
    end
  end

  def test_array_items
    with_types do
      klass = define { array :site_ids, type: :site_id, item_schema_options: {min_length: 6} }

      assert_equal({"type" => "string", "pattern" => "^site_", "minLength" => 6}, properties(klass)["site_ids"]["items"])
    end
  end

  def test_formatters_come_from_the_custom_format
    with_types do
      klass = define do
        field :created_at, type: :datetime
        field :due_on, type: :date
        array :seen_at, type: :datetime
      end
      time = Time.new(2025, 9, 1, 13, 30, 0, "+01:00")

      assert_equal({"created_at" => "2025-09-01T12:30:00.000Z", "due_on" => "2025-09-01", "seen_at" => ["2025-09-01T12:30:00.000Z"]},
        klass.serialize({created_at: time, due_on: time, seen_at: [time]}, version: "2025-09"))
    end
  end

  def test_output_validation_checks_custom_schemas
    with_types do
      klass = define do
        field :id, type: :site_id
        field :notification, type: :price_adjustment_notification
      end

      with_configuration(validate_output: true) do
        assert_equal "site_1", klass.serialize({id: "site_1", notification: {notice_period: 30}}, version: "2025-09")["id"]
        assert_raises(Versponse::InvalidOutputError) { klass.serialize({id: "unit_1", notification: {notice_period: 30}}, version: "2025-09") }
        assert_raises(Versponse::InvalidOutputError) { klass.serialize({id: "site_1", notification: {notice_period: 0}}, version: "2025-09") }
      end
    end
  end

  def test_every_stora_type_compiles
    with_types do
      klass = define { STORA_FIELD_TYPES.each_key { |type| field type, type: } }

      assert_equal STORA_FIELD_TYPES.keys.map(&:to_s), properties(klass).keys
      assert_kind_of JSONSchemer::Schema, klass.versponse.schemer(version: "2025-09")
    end
  end

  def test_unknown_type
    error = assert_raises(Versponse::DefinitionError) { define { field :id, type: :site_id } }

    assert_equal "id: type must be one of string, number, integer, boolean, object", error.message
  end
end
