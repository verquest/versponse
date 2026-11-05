# frozen_string_literal: true

module Versponse
  module Validator
    # Combines the checkers of one schema; all must pass
    #
    # @api private
    class All
      # @param checkers [Array<#valid?>] checkers of one schema
      # @return [#valid?] VALID for none, the checker itself for one, else an All
      def self.for(checkers)
        return Constant::VALID if checkers.empty?
        return checkers.first if checkers.one?

        new(checkers)
      end

      # @param checkers [Array<#valid?>] two or more checkers
      def initialize(checkers)
        @checkers = checkers.freeze
        freeze
      end

      # @param data [Object] value to check
      # @return [Boolean] true when every checker passes
      def valid?(data)
        @checkers.all? { |checker| checker.valid?(data) }
      end
    end
  end
end
