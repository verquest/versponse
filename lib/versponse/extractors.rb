# frozen_string_literal: true

module Versponse
  # Value readers chosen once at compile time. Each is called with (object, hash, context),
  # where hash tells whether the object is a Hash.
  #
  # @api private
  module Extractors
    # @param name [Symbol] property name
    # @param map [String, nil] map: path
    # @param block [Proc, nil] value block
    # @return [#call] the extractor for the property
    def self.for(name:, map:, block:)
      return Block.new(Callable.normalize(block)) if block
      return Key.new(name) if map.nil?
      return Itself::INSTANCE if map == "."
      raise DefinitionError, "map: #{map.inspect} must be a non-empty path without empty segments" if map.empty? || map.split("/", -1).any?(&:empty?)
      return Path.new(map.split("/")) if map.include?("/")

      Key.new(map)
    end
  end
end
