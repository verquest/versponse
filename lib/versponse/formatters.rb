# frozen_string_literal: true

module Versponse
  # Default formatters, keyed by JSON Schema format, applied to non-nil field values
  module Formatters
    # Formats times, datetimes and dates (as midnight) as ISO 8601 in UTC, always with a Z suffix, without changing the original object
    DATE_TIME = lambda do |value|
      if value.respond_to?(:getutc)
        value.getutc.iso8601
      elsif value.respond_to?(:new_offset)
        value.new_offset(0).to_time.utc.iso8601
      elsif value.is_a?(Date)
        Time.utc(value.year, value.month, value.day).iso8601
      else
        value
      end
    end

    # Formats dates, and times or datetimes (converted to their date), as ISO 8601
    DATE = ->(value) { (value.is_a?(Date) || value.is_a?(Time)) ? value.to_date.iso8601 : value }

    # Formatters used when none are configured
    DEFAULTS = {"date-time" => DATE_TIME, "date" => DATE}.freeze
  end
end
