# frozen_string_literal: true

module Versponse
  module Validator
    # anyOf, oneOf and allOf
    #
    # @api private
    class Combinator
      # Keywords and the Enumerable predicate each applies to its branches
      MODES = {"anyOf" => :any?, "oneOf" => :one?, "allOf" => :all?}.freeze

      # @return [Array<String>] keywords this check owns
      def self.keywords = MODES.keys

      # @param schema [Hash] schema
      # @param compiler [Versponse::Validator::Compiler] compiles the branches
      # @return [#valid?, nil] the check, nil without combinators
      def self.build(schema, compiler)
        combinators = MODES.filter_map do |keyword, mode|
          new(schema[keyword].map { |branch| compiler.compile(branch) }, mode) if schema.key?(keyword)
        end
        All.for(combinators) unless combinators.empty?
      end

      # @param branches [Array<#valid?>] checkers of the branches
      # @param mode [Symbol] :any?, :one? or :all?
      def initialize(branches, mode)
        @branches = branches.freeze
        @mode = mode
        freeze
      end

      # @param data [Object] value to check
      # @return [Boolean] true when the branches match as the mode requires
      def valid?(data)
        @branches.public_send(@mode) { |branch| branch.valid?(data) }
      end
    end
  end
end
