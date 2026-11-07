# frozen_string_literal: true

module Versponse
  module Steps
    # A plain field: reads a method or Hash key and formats it, with no condition, block or path.
    # The common case, without Value's extractor and condition layers.
    #
    # @api private
    class Read
      # @return [String] output key
      attr_reader :key

      # @param key [String] output key
      # @param name [String, Symbol] method or Hash key to read
      # @param formatter [#call, nil] applied to non-nil values
      def initialize(key:, name:, formatter: nil)
        @key = key
        @symbol = name.to_sym
        @string = name.to_s.freeze
        @formatter = formatter
        freeze
      end

      # @param check [#valid?] checker of the property's schema
      # @return [CheckedRead] the same read, checking what it writes
      def checked(check)
        CheckedRead.new(key: @key, name: @string, formatter: @formatter, check:)
      end

      # @return [Boolean] false: a read has no if:/unless:
      def conditional?
        false
      end

      # @param object [Object] source
      # @param hash [Boolean] whether the source is a Hash
      # @param _context [Hash] unused
      # @param output [Hash] Hash being built
      # @param _expansion [Versponse::Expansion] unused
      # @return [void]
      # @raise [KeyError] when a Hash has neither key; NoMethodError when an object has no such method
      def call(object, hash, _context, output, _expansion)
        output[@key] = hash ? object.fetch(@symbol) { object.fetch(@string) } : object.public_send(@symbol)
      end
    end
  end
end
