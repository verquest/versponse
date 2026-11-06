# frozen_string_literal: true

module Versponse
  # Frozen tree of requested expand paths, passed down while rendering. Each node answers whether
  # a key is expanded and hands out the node for that key's children.
  #
  # @api private
  class Expansion
    # @param paths [Array<String, Symbol>] dotted paths
    # @return [Expansion] the tree (NONE for no paths)
    def self.build(paths)
      tree = {}
      paths.map(&:to_s).each { |path| path.split(".").reduce(tree) { |node, key| node[key] ||= {} } }
      from_hash(tree)
    end

    # @param hash [Hash{String => Hash}] nested keys
    # @return [Expansion] the frozen node
    def self.from_hash(hash)
      return NONE if hash.empty?

      new(hash.transform_values { |child| from_hash(child) })
    end

    # @param children [Hash{String => Expansion}] expanded keys and their nodes
    def initialize(children = {})
      @children = children.freeze
      freeze
    end

    # @param key [String] output key
    # @return [Boolean] whether the association under key is expanded
    def expand?(key)
      @children.key?(key)
    end

    # @param key [String] output key
    # @return [Expansion] the node for the key's children
    def child(key)
      @children.fetch(key, NONE)
    end

    # Nothing expanded
    NONE = new
  end
end
