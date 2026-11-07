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
    # @return [Array<String>] keys rendered whatever a selection says: identifiers and consts
    attr_reader :always

    # @param label [String] plan label
    # @param steps [Array<#call>] compiled steps
    # @param recoveries [Array<Versponse::ErrorPolicy::Recovery, nil>, nil] recovery per step
    # @param always [Array<String>] identifier keys (consts are found among the steps)
    def initialize(label:, steps:, recoveries: nil, always: [])
      @label = label
      @steps = steps.dup.freeze
      @recoveries = recoveries
      @always = (always + @steps.grep(Steps::Const).map(&:key)).uniq.freeze
      freeze
    end

    # A step whose recovery accepts its error is recovered and the loop goes on with the next step (retry restarts
    # the begin block only, so output and index keep their values). An error from the recovery itself (a handler or
    # the hook) is raised from the rescue clause, outside the begin block, so it propagates.
    #
    # @param object [Object] source object or Hash
    # @param context [Hash] frozen serialize context
    # @param expansion [Versponse::Expansion, Versponse::Selection::Scope] expand tree node for this object, paired with
    #   its selection in a selected render
    # @return [Hash{String => Object}] rendered object
    # @raise [Versponse::ExtractionError] when a step raises NoMethodError or KeyError that no policy recovers (the
    #   original error is kept as `cause`); other errors no policy recovers propagate unchanged
    def call(object, context, expansion = Expansion::NONE)
      return call_selected(object, context, expansion) if Selection::Scope === expansion

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
        recover!(e, steps[index], index, object, context, output)
        index += 1
        retry
      end
      output
    end

    private

    # A selected render walks the step indexes its selection memoizes for this plan
    def call_selected(object, context, scope)
      output = {}
      steps = @steps
      indexes = scope.selection.indexes_for(self)
      position = 0
      hash = Hash === object
      begin
        while position < indexes.size
          steps[indexes[position]].call(object, hash, context, output, scope)
          position += 1
        end
      rescue => e
        index = indexes[position]
        recover!(e, steps[index], index, object, context, output)
        position += 1
        retry
      end
      output
    end

    # Recovers the step's error with its policy, or raises it (as an ExtractionError for NoMethodError and KeyError)
    def recover!(error, step, index, object, context, output)
      recovery = @recoveries&.[](index)
      raise extraction_error(error, step) unless recovery&.recovers?(error)

      recovery.recover(error, object, context, output)
    end

    def extraction_error(error, step)
      case error
      when ExtractionError then ExtractionError.new(label:, keys: [step&.key, *error.keys].compact, detail: error.detail)
      when NoMethodError, KeyError then ExtractionError.new(label:, keys: [step&.key].compact, detail: error.message)
      else error
      end
    end
  end
end
