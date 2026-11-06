# frozen_string_literal: true

module Versponse
  module Validator
    # format, checked with json_schemer's own format procs
    #
    # @api private
    class FormatCheck
      # @return [Array<String>] keywords this check owns
      def self.keywords = %w[format]

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
      def initialize(name, check)
        @name = name
        @check = check
        freeze
      end

      # @param data [Object] value to check (each format proc skips types it doesn't apply to)
      # @return [Boolean] true when data matches the format
      def valid?(data)
        @check.call(data, @name)
      end
    end
  end
end
