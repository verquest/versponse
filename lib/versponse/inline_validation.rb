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

    # @return [void]
    def self.failed!
      Thread.current[FLAG] = true
    end

    # Runs a render with a clear flag; the previous value is restored, so a serialize inside a block is isolated
    #
    # @yield the render (it keeps its result itself, so nothing is allocated here)
    # @return [Boolean] true when a check failed
    def self.run
      previous = Thread.current[FLAG]
      Thread.current[FLAG] = false
      yield
      Thread.current[FLAG]
    ensure
      Thread.current[FLAG] = previous
    end
  end
end
