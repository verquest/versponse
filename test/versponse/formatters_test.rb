# frozen_string_literal: true

require "test_helper"

class Versponse::FormattersTest < Minitest::Test
  def test_date_time_formats_times_in_utc_without_changing_them
    time = Time.new(2025, 9, 1, 12, 0, 0, "+02:00")

    assert_equal "2025-09-01T10:00:00.000Z", Versponse::Formatters::DATE_TIME.call(time)
    assert_equal "+02:00", time.strftime("%:z")
  end

  # Milliseconds, like Rails' JSON encoding, so ordering and round-trips keep sub-second precision
  def test_date_time_keeps_milliseconds
    assert_equal "1970-01-01T00:00:01.123Z", Versponse::Formatters::DATE_TIME.call(Time.at(1, 123_456, :usec))
  end

  def test_date_time_formats_datetimes_in_utc
    assert_equal "2025-09-01T10:00:00.000Z", Versponse::Formatters::DATE_TIME.call(DateTime.new(2025, 9, 1, 12, 0, 0, "+02:00"))
  end

  def test_date_time_formats_dates_as_utc_midnight
    assert_equal "2025-09-01T00:00:00.000Z", Versponse::Formatters::DATE_TIME.call(Date.new(2025, 9, 1))
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

  # A UTC Time is formatted without the getutc copy; the output is the same as for any other Time
  def test_date_time_formats_utc_times_without_copying
    utc = Time.utc(2025, 9, 1, 10, 0, 0, 123_456)
    local = Time.new(2025, 9, 1, 12, 0, 0.123456r, "+02:00")

    assert_equal "2025-09-01T10:00:00.123Z", Versponse::Formatters::DATE_TIME.call(utc)
    assert_equal Versponse::Formatters::DATE_TIME.call(local), Versponse::Formatters::DATE_TIME.call(utc)
    utc.define_singleton_method(:getutc) { raise "getutc copies a UTC Time" }

    assert_equal "2025-09-01T10:00:00.123Z", Versponse::Formatters::DATE_TIME.call(utc)
  end

  # Built Strings are frozen, so inline validation checks them once; a String input comes back as it is
  def test_built_strings_are_frozen
    time = Time.utc(2025, 9, 1, 10)
    input = +"2025"

    assert_predicate Versponse::Formatters::DATE_TIME.call(time), :frozen?
    assert_predicate Versponse::Formatters::DATE_TIME.call(Date.new(2025, 9, 1)), :frozen?
    assert_predicate Versponse::Formatters::DATE.call(time), :frozen?
    assert_same input, Versponse::Formatters::DATE.call(input)
  end
end
