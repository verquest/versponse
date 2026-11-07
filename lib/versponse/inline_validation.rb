# frozen_string_literal: true

module Versponse
  # Validation while rendering: checked steps report a failure through a fiber-local flag, and the finished output
  # then goes through OutputValidator as before. Collections.items materializes collections (to_ary/to_a), so a
  # render never switches fibers halfway; keep it that way.
  #
  # @api private
  module InlineValidation
    # Fiber-local key of the flag (Thread#[] is fiber-local)
    FLAG = :versponse_inline_invalid

    # Fiber-local key of the checks to run again after the render
    RECHECKS = :versponse_inline_rechecks

    # @return [void]
    def self.failed!
      Thread.current[FLAG] = true
    end

    # An Array or Hash a check accepted can still be changed in place by a later step of the same render (the
    # value is often the source's own object), so its check runs again once the render has finished
    #
    # @param check [#valid?] checker that accepted the value
    # @param value [Array, Hash] unfrozen value
    # @return [void]
    def self.recheck_later(check, value)
      (Thread.current[RECHECKS] ||= []).push(check, value)
    end

    # Runs a render with a clear flag; the previous state is restored, so a serialize inside a block is isolated
    #
    # @yield the render (it keeps its result itself, so nothing is allocated here)
    # @return [Boolean] true when a check failed, during the render or when rechecked after it
    def self.run
      previous = Thread.current[FLAG]
      previous_rechecks = Thread.current[RECHECKS]
      Thread.current[FLAG] = false
      Thread.current[RECHECKS] = nil
      yield
      rechecks = Thread.current[RECHECKS]
      failed! if rechecks && !rechecked?(rechecks)
      Thread.current[FLAG]
    ensure
      Thread.current[FLAG] = previous
      Thread.current[RECHECKS] = previous_rechecks
    end

    # @param rechecks [Array] checkers and values, alternating
    # @return [Boolean] true when every value still passes its check
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
