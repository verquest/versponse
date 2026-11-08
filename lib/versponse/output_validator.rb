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
    # @param selection [Versponse::Selection] the render's selection; a selected render is checked against the
    #   pruned validation schema
    # @return [void]
    # @raise [Versponse::InvalidOutputError] when the output does not match
    def self.call(klass, data, version:, view:, selection: Selection::ALL)
      checker, schemer = selection.all? ? [klass.versponse.checker(version:, view:), nil] : klass.versponse.selected_validators(version:, view:, selection:)
      return if valid?(checker, data)

      schemer ||= klass.versponse.schemer(version:, view:)
      errors = if data.is_a?(Array)
        data.each_with_index.flat_map { |item, index| errors_for(schemer, item, "/#{index}") }
      else
        errors_for(schemer, data, "")
      end
      return if errors.empty?

      raise InvalidOutputError.new("#{klass.name || "AnonymousResponse"} output does not match its #{version}/#{view} schema", errors:)
    end

    # Whether this render is validated: validate_output must allow it (true, or a callable returning truthy for
    # the class), and the render must be sampled; the cheap checks run first, so a callable runs only on sampled renders
    #
    # @param klass [Class] response class serialize was called on
    # @return [Boolean] true when the render is validated
    def self.enabled?(klass)
      config = Versponse.configuration
      setting = config.validate_output
      return false unless setting

      rate = config.validate_output_sample_rate
      return false if rate < 1 && Random.rand >= rate

      setting == true || !!setting.call(klass)
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
