# frozen_string_literal: true

module Versponse
  module Validator
    # $ref to a local $anchor ("#Name"), resolved when validating so recursive schemas work
    #
    # @api private
    class Ref
      # @return [Array<String>] keywords this check owns
      def self.keywords = %w[$ref]

      # @param schema [Hash] schema
      # @param compiler [Versponse::Validator::Compiler] registers the reference
      # @return [Ref, nil] the check, nil without $ref
      # @raise [Versponse::Validator::Compiler::Unsupported] for anything but a plain-name fragment
      def self.build(schema, compiler)
        return unless schema.key?("$ref")
        raise Compiler::Unsupported, schema["$ref"] unless schema["$ref"].match?(/\A#[A-Za-z_][-A-Za-z0-9._]*\z/)

        compiler.ref(schema["$ref"].delete_prefix("#"))
      end

      # @param anchors [Hash{String => #valid?}] anchors of the root schema, filled while compiling
      # @param name [String] anchor name
      def initialize(anchors, name)
        @anchors = anchors
        @name = name
        freeze
      end

      # @param data [Object] value to check
      # @return [Boolean] true when data matches the anchored schema
      def valid?(data)
        @anchors.fetch(@name).valid?(data)
      end
    end
  end
end
