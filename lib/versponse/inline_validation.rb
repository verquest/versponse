# frozen_string_literal: true

module Versponse
  # Validation while rendering: checked steps report a failure through a fiber-local flag, and the finished output
  # then goes through OutputValidator as before. Collections.items materializes collections (to_ary/to_a), so a
  # render never switches fibers halfway; keep it that way.
  #
  # @api private
  module InlineValidation
    # Fiber-local key of the State (Thread#[] is fiber-local)
    STATE = :versponse_inline_validation

    # Marks the current run as failed; outside a run (a plain render's recovery) it does nothing
    #
    # @return [void]
    def self.failed!
      state = Thread.current[STATE]
      state.failed = true if state && !state.failed.nil?
    end

    # @param check [#valid?] checker of the value's schema
    # @param value [Object] value to check once the render has finished
    # @return [void]
    def self.recheck_later(check, value)
      state = Thread.current[STATE]
      (state.rechecks ||= []).push(check, value)
    end

    # @return [Boolean] true while a run is active in this fiber and one of its checks failed
    def self.failed?
      Thread.current[STATE]&.failed == true
    end

    # Checks a value a step wrote. A value that a later step of the same render could still change in place (it is
    # often the source's own object) is checked once the render has finished instead: any value that isn't frozen
    # all the way down, when the schema can be broken by such a change. A check that raises, or defers
    # (UncaughtThrowError outside Root), fails.
    #
    # @param check [#valid?] checker of the value's schema
    # @param value [Object] written value
    # @param recheck [Boolean] whether a change in place can break the schema (see Builder)
    # @return [void]
    def self.check(check, value, recheck)
      if recheck && !Ractor.shareable?(value)
        recheck_later(check, value)
      else
        ok = begin
          check.valid?(value)
        rescue
          false
        end
        failed! unless ok
      end
    end

    # Runs a render with a clear flag; the previous state is restored, so a serialize inside a block is isolated
    #
    # @yield the render (it keeps its result itself, so nothing is allocated here)
    # @return [Boolean] true when a check failed, during the render or when rechecked after it
    def self.run
      state = (Thread.current[STATE] ||= State.new)
      previous = state.failed
      previous_rechecks = state.rechecks
      state.failed = false
      state.rechecks = nil
      yield
      rechecks = state.rechecks
      state.failed = true if rechecks && !rechecked?(rechecks)
      state.failed
    ensure
      state.failed = previous
      state.rechecks = previous_rechecks
    end

    # @param rechecks [Array] checkers and values, alternating
    # @return [Boolean] true when every value passes its check
    def self.rechecked?(rechecks)
      rechecks.each_slice(2).all? do |check, value|
        check.valid?(value)
      rescue
        false
      end
    end
    private_class_method :rechecked?
  end
end
