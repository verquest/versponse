# frozen_string_literal: true

module Versponse
  module InlineValidation
    # A fiber's inline validation state, kept in one fiber-local so a render reads it once
    #
    # @api private
    class State
      # @return [Boolean, nil] whether a check failed in the current run, nil outside a run
      attr_accessor :failed

      # @return [Array, nil] checkers and values (alternating) to check once the render has finished
      attr_accessor :rechecks
    end
  end
end
