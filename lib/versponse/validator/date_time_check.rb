# frozen_string_literal: true

module Versponse
  module Validator
    # The date-time format, with a fast path for the timestamps Versponse renders. A String matching
    # {FAST} is valid without json_schemer; everything else is left to json_schemer's check.
    #
    # @api private
    class DateTimeCheck < FormatCheck
      # RFC 3339 date-times that json_schemer certainly accepts: days 01-28 (no calendar check needed), no leap
      # seconds, uppercase T and Z, bounded offsets, anchored. Fuzzed against json_schemer 2.5.0 with no false accept.
      FAST = /\A\d{4}-(0[1-9]|1[0-2])-(0[1-9]|1\d|2[0-8])T([01]\d|2[0-3]):[0-5]\d:[0-5]\d(\.\d+)?(Z|[+-]([01]\d|2[0-3]):[0-5]\d)\z/

      # @param data [Object] value to check; anything but a String passes, as in json_schemer
      # @return [Boolean] true when data is a valid date-time
      def valid?(data)
        !data.is_a?(String) || FAST.match?(data) || super
      end
    end
  end
end
