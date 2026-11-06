# frozen_string_literal: true

require "test_helper"

class TimePrecisionTest < Minitest::Test
  include ConfigurationTestHelper

  Event = Struct.new(:at, :times, :detail)
  AT = Time.utc(2025, 9, 1, 10, 0, 0, 123_456)

  class BaseResponse < Versponse::Base
    time_precision 0
    time_precision 3, from: "2026-03"
  end

  class DetailResponse < Versponse::Base
    version "2025-09" do
      field :at, type: :string, format: "date-time"
    end
  end

  class EventResponse < BaseResponse
    version "2025-09" do
      field :at, type: :string, format: "date-time"
      array :times, type: :string, item_schema_options: {format: "date-time"}
      object(:inline, map: ".") { field :at, type: :string, format: "date-time" }
      reference :detail, from: DetailResponse
    end
  end

  class MicrosecondResponse < BaseResponse
    time_precision 6, from: "2027-01"

    version "2025-09" do
      field :at, type: :string, format: "date-time"
    end
  end

  def event(at = AT) = Event.new(at:, times: [at], detail: Event.new(at:))

  def test_the_default_keeps_milliseconds
    assert_equal "2025-09-01T10:00:00.123Z", DetailResponse.serialize(event, version: "2025-09")["at"]
  end

  def test_applies_the_setting_of_the_requested_version
    assert_equal "2025-09-01T10:00:00Z", EventResponse.serialize(event, version: "2025-09")["at"]
    assert_equal "2025-09-01T10:00:00.123Z", EventResponse.serialize(event, version: "2026-03")["at"]
  end

  def test_applies_from_a_version_no_class_declares
    assert_equal "2025-09-01T10:00:00Z", EventResponse.serialize(event, version: "2026-02")["at"]
    assert_equal "2025-09-01T10:00:00.123Z", EventResponse.serialize(event, version: "2026-05")["at"]
  end

  def test_formats_arrays_and_inline_objects_of_the_class
    result = EventResponse.serialize(event, version: "2025-09")

    assert_equal ["2025-09-01T10:00:00Z"], result["times"]
    assert_equal "2025-09-01T10:00:00Z", result["inline"]["at"]
  end

  def test_a_nested_class_uses_its_own_setting
    assert_equal "2025-09-01T10:00:00.123Z", EventResponse.serialize(event, version: "2025-09")["detail"]["at"]
  end

  def test_subclasses_inherit_and_add_settings
    assert_equal "2025-09-01T10:00:00Z", MicrosecondResponse.serialize(event, version: "2025-09")["at"]
    assert_equal "2025-09-01T10:00:00.123Z", MicrosecondResponse.serialize(event, version: "2026-03")["at"]
    assert_equal "2025-09-01T10:00:00.123456Z", MicrosecondResponse.serialize(event, version: "2027-01")["at"]
  end

  def test_replaces_a_configured_date_time_formatter
    with_configuration(formatters: Versponse::Formatters::DEFAULTS.merge("date-time" => ->(value) { value.getutc.iso8601(1) })) do
      assert_equal "2025-09-01T10:00:00Z", EventResponse.serialize(event, version: "2025-09")["at"]
      assert_equal "2025-09-01T10:00:00.1Z", DetailResponse.serialize(event, version: "2025-09")["at"]
    end
  end

  def test_formats_dates_and_datetimes
    assert_equal "2025-09-01T00:00:00Z", EventResponse.serialize(event(Date.new(2025, 9, 1)), version: "2025-09")["at"]
    assert_equal "2025-09-01T10:00:00Z", EventResponse.serialize(event(DateTime.new(2025, 9, 1, 11, 0, 0, "+01:00")), version: "2025-09")["at"]
  end

  def test_schemas_do_not_change
    assert_equal({"type" => "string", "format" => "date-time"}, EventResponse.to_schema(version: "2025-09")["properties"]["at"])
  end

  def test_invalid_declarations_raise
    assert_raises(Versponse::DefinitionError) { Class.new(Versponse::Base) { time_precision 10 } }
    assert_raises(Versponse::DefinitionError) { Class.new(Versponse::Base) { time_precision "3" } }
    assert_raises(Versponse::DefinitionError) { Class.new(Versponse::Base) { version("2025-09") { time_precision 0 } } }
    assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) do
        version("2025-09") { field :at, type: :string }
        time_precision 0
      end
    end
    assert_raises(Versponse::DefinitionError) do
      Class.new(Versponse::Base) do
        time_precision 0, from: "2026-03"
        time_precision 3, from: "2026-03"
      end
    end
  end
end
