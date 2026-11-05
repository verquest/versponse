# frozen_string_literal: true

require "test_helper"

class Versponse::FormattersTest < Minitest::Test
  def test_date_time_formats_times_in_utc_without_changing_them
    time = Time.new(2025, 9, 1, 12, 0, 0, "+02:00")

    assert_equal "2025-09-01T10:00:00Z", Versponse::Formatters::DATE_TIME.call(time)
    assert_equal "+02:00", time.strftime("%:z")
  end

  def test_date_time_formats_datetimes_in_utc
    assert_equal "2025-09-01T10:00:00Z", Versponse::Formatters::DATE_TIME.call(DateTime.new(2025, 9, 1, 12, 0, 0, "+02:00"))
  end

  def test_date_time_formats_dates_as_utc_midnight
    assert_equal "2025-09-01T00:00:00Z", Versponse::Formatters::DATE_TIME.call(Date.new(2025, 9, 1))
  end

  def test_date_time_passes_other_values_through
    assert_equal "2025", Versponse::Formatters::DATE_TIME.call("2025")
  end

  def test_date_formats_times_as_dates
    assert_equal "2025-09-01", Versponse::Formatters::DATE.call(Time.new(2025, 9, 1, 23, 0, 0, "+02:00"))
  end

  def test_date_keeps_strings
    assert_equal "soon", Versponse::Formatters::DATE.call("soon")
  end

  def test_date_formats_with_iso8601
    assert_equal "2025-09-01", Versponse::Formatters::DATE.call(Date.new(2025, 9, 1))
  end
end
