# frozen_string_literal: true

module Versponse
  module Extractors
    # Reads a nested value like "address/city", returning nil when a step is nil
    #
    # @api private
    class Path
      # @param segments [Array<String>] path segments
      def initialize(segments)
        @keys = segments.map { |segment| Key.new(segment) }.freeze
        freeze
      end

      # @param object [Object] source
      # @param _hash [Boolean] unused, each step checks its own source
      # @param context [Hash] serialize context
      # @return [Object, nil] the value
      def call(object, _hash, context)
        @keys.reduce(object) do |current, key|
          return nil if current.nil?

          key.call(current, current.is_a?(Hash), context)
        end
      end
    end
  end
end
