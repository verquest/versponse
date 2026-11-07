# frozen_string_literal: true

module Versponse
  # Compiled, frozen list of steps that turns one object into a Hash
  #
  # @api private
  class Plan
    # @return [String] label used in extraction errors, like "UserResponse[2025-09/default]"
    attr_reader :label
    # @return [Array<#call>] compiled steps
    attr_reader :steps
    # @return [Array<Versponse::ErrorPolicy::Recovery, nil>, nil] recovery per step, nil when every step raises
    attr_reader :recoveries

    # @param label [String] plan label
    # @param steps [Array<#call>] compiled steps
    # @param recoveries [Array<Versponse::ErrorPolicy::Recovery, nil>, nil] recovery per step
    def initialize(label:, steps:, recoveries: nil)
      @label = label
      @steps = steps.dup.freeze
      @recoveries = recoveries
      freeze
    end

    # A step whose recovery accepts its error is recovered and the loop goes on with the next step (retry restarts
    # the begin block only, so output and index keep their values). An error from the recovery itself (a handler or
    # the hook) is raised from the rescue clause, outside the begin block, so it propagates.
    #
    # @param object [Object] source object or Hash
    # @param context [Hash] frozen serialize context
    # @param expansion [Versponse::Expansion] expand tree node for this object
    # @return [Hash{String => Object}] rendered object
    # @raise [Versponse::ExtractionError] when a step raises NoMethodError or KeyError that no policy recovers (the
    #   original error is kept as `cause`); other errors no policy recovers propagate unchanged
    def call(object, context, expansion = Expansion::NONE)
      output = {}
      steps = @steps
      index = 0
      hash = Hash === object
      begin
        while index < steps.size
          steps[index].call(object, hash, context, output, expansion)
          index += 1
        end
      rescue => e
        recovery = @recoveries&.[](index)
        raise extraction_error(e, steps[index]) unless recovery&.recovers?(e)

        recovery.recover(e, object, context, output)
        index += 1
        retry
      end
      output
    end

    private

    def extraction_error(error, step)
      case error
      when ExtractionError then ExtractionError.new(label:, keys: [step&.key, *error.keys].compact, detail: error.detail)
      when NoMethodError, KeyError then ExtractionError.new(label:, keys: [step&.key].compact, detail: error.message)
      else error
      end
    end
  end
end
