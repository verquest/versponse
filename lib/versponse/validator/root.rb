# frozen_string_literal: true

module Versponse
  module Validator
    # Compiled checker of a whole schema. A check that can't answer (a non-String key) throws {DEFER},
    # which this root turns into false, so the caller asks json_schemer, instead of a false that a
    # oneOf or not further up would read as a real answer.
    #
    # @api private
    class Root
      # Thrown by a check that leaves the value to json_schemer
      DEFER = :versponse_validator_defer

      # @param checker [#valid?] compiled checker
      def initialize(checker)
        @checker = checker
        freeze
      end

      # @param data [Object] value to check
      # @return [Boolean] true when the value matches; false when it doesn't or json_schemer has to decide
      def valid?(data)
        catch(DEFER) { return @checker.valid?(data) }
        false
      end
    end
  end
end
