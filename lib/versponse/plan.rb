# frozen_string_literal: true

module Versponse
  # Compiled, frozen list of steps that turns one object into a Hash
  #
  # @api private
  class Plan
    # @return [String] label used in extraction errors, like "UserResponse[2025-09/default]"
    attr_reader :label

    # @param label [String] plan label
    # @param steps [Array<#call>] compiled steps
    def initialize(label:, steps:)
      @label = label
      @steps = steps.dup.freeze
      freeze
    end

    # @param object [Object] source object or Hash
    # @param context [Hash] frozen serialize context
    # @param expansion [Versponse::Expansion] expand tree node for this object
    # @return [Hash{String => Object}] rendered object
    # @raise [Versponse::ExtractionError] when a step (extractor, condition, block or formatter)
    #   raises NoMethodError or KeyError; the original error is kept as `cause`
    def call(object, context, expansion = Expansion::NONE)
      output = {}
      steps = @steps
      index = 0
      hash = Hash === object
      while index < steps.size
        steps[index].call(object, hash, context, output, expansion)
        index += 1
      end
      output
    rescue ExtractionError => e
      raise ExtractionError.new(label:, keys: [steps[index]&.key, *e.keys].compact, detail: e.detail)
    rescue NoMethodError, KeyError => e
      raise ExtractionError.new(label:, keys: [steps[index]&.key].compact, detail: e.message)
    end
  end
end
