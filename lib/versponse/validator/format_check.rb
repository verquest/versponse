# frozen_string_literal: true

module Versponse
  module Validator
    # format, checked with json_schemer's own format procs
    #
    # @api private
    class FormatCheck
      # @return [Array<String>] keywords this check owns
      def self.keywords = %w[format]

      # @return [Class] the class a type folded into this check requires
      def self.shape = String

      # @param schema [Hash] schema
      # @param compiler [Versponse::Validator::Compiler] looks formats up like json_schemer
      # @return [FormatCheck, nil] the check, nil without format or for an unknown one (which accepts anything)
      def self.build(schema, compiler)
        return unless schema.key?("format")

        check = compiler.format(schema["format"])
        return unless check

        (schema["format"] == "date-time") ? DateTimeCheck.new(schema["format"], check) : new(schema["format"], check)
      end

      # @param name [String] format name
      # @param check [Proc] json_schemer's check, called with (data, name)
      # @param strict [Boolean] true when anything but a String fails (type: "string" folded in)
      def initialize(name, check, strict: false)
        @name = name
        @check = check
        @strict = strict
        freeze
      end

      # @return [FormatCheck] the same check, failing anything but a String
      def strict
        self.class.new(@name, @check, strict: true)
      end

      # @param data [Object] value to check (each format proc skips types it doesn't apply to; strict fails them)
      # @return [Boolean] true when data matches the format
      def valid?(data)
        (@strict && !data.is_a?(String)) ? false : @check.call(data, @name)
      end
    end
  end
end
