# frozen_string_literal: true

module Versponse
  # Default formatters, keyed by JSON Schema format, applied to non-nil field values
  module Formatters
    # Formats times, datetimes and dates (as midnight) as ISO 8601 in UTC with the given fraction digits,
    # always with a Z suffix, without changing the original object
    #
    # @param precision [Integer] fraction digits, 0 for whole seconds
    # @return [Proc] date-time formatter
    def self.date_time(precision)
      lambda do |value|
        if value.respond_to?(:getutc)
          value.getutc.iso8601(precision)
        elsif value.respond_to?(:new_offset)
          value.new_offset(0).to_time.utc.iso8601(precision)
        elsif value.is_a?(Date)
          Time.utc(value.year, value.month, value.day).iso8601(precision)
        else
          value
        end
      end
    end

    # Formats date-times with milliseconds, like Rails' JSON
    DATE_TIME = date_time(3)

    # Formats dates, and times or datetimes (converted to their date), as ISO 8601
    DATE = ->(value) { (value.is_a?(Date) || value.is_a?(Time)) ? value.to_date.iso8601 : value }

    # Formatters used when none are configured
    DEFAULTS = {"date-time" => DATE_TIME, "date" => DATE}.freeze
  end
end
