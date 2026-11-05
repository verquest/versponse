# frozen_string_literal: true

module Versponse
  # Validates rendered output against its validation schema (config.validate_output)
  #
  # @api private
  module OutputValidator
    # @param klass [Class] response class
    # @param data [Hash, Array<Hash>] rendered output, before root/meta wrapping
    # @param version [String] requested version name
    # @param view [Symbol] view name
    # @return [void]
    # @raise [Versponse::InvalidOutputError] when the output does not match
    def self.call(klass, data, version:, view:)
      return if valid?(klass.checker(version:, view:), data)

      schemer = klass.schemer(version:, view:)
      errors = if data.is_a?(Array)
        data.each_with_index.flat_map { |item, index| errors_for(schemer, item, "/#{index}") }
      else
        errors_for(schemer, data, "")
      end
      return if errors.empty?

      raise InvalidOutputError.new("#{klass.name} output does not match its #{version}/#{view} schema", errors:)
    end

    # The compiled checker is the fast path; json_schemer runs only when it fails or is missing
    #
    # @param checker [#valid?, nil] compiled checker of the schema
    # @param data [Hash, Array<Hash>] rendered output
    # @return [Boolean] true when the checker accepts every item
    def self.valid?(checker, data)
      return false unless checker

      data.is_a?(Array) ? data.all? { |item| checker.valid?(item) } : checker.valid?(data)
    end

    # @param schemer [JSONSchemer::Schema] compiled schema
    # @param data [Hash] one rendered object
    # @param prefix [String] pointer prefix for collection items
    # @return [Array<Hash>] errors with :pointer, :type, :message and :details
    def self.errors_for(schemer, data, prefix)
      schemer.validate(data).map do |error|
        {pointer: prefix + error["data_pointer"], type: error["type"], message: error["error"], details: error["details"]}
      end
    end
  end
end
