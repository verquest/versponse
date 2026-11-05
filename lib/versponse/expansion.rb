# frozen_string_literal: true

module Versponse
  # Frozen tree of requested expand paths, passed down while rendering. Each node answers whether
  # a key is expanded and hands out the node for that key's children.
  #
  # @api private
  class Expansion
    # @param paths [Array<String, Symbol>] dotted paths, or "*" for everything
    # @return [Expansion] the tree (NONE for no paths, ALL for "*")
    def self.build(paths)
      paths = paths.map(&:to_s)
      return ALL if paths.include?("*")

      tree = {}
      paths.each { |path| path.split(".").reduce(tree) { |node, key| node[key] ||= {} } }
      from_hash(tree)
    end

    # @param hash [Hash{String => Hash}] nested keys
    # @return [Expansion] the frozen node
    def self.from_hash(hash)
      return NONE if hash.empty?

      new(hash.transform_values { |child| from_hash(child) })
    end

    # @param children [Hash{String => Expansion}] expanded keys and their nodes
    # @param all [Boolean] true for the node that expands everything at every depth
    def initialize(children = {}, all: false)
      @children = children.freeze
      @all = all
      freeze
    end

    # @param key [String] output key
    # @return [Boolean] whether the association under key is expanded
    def expand?(key)
      @all || @children.key?(key)
    end

    # @param key [String] output key
    # @return [Expansion] the node for the key's children
    def child(key)
      @all ? self : @children.fetch(key, NONE)
    end

    # Nothing expanded
    NONE = new
    # Everything expanded, at every depth
    ALL = new(all: true)
  end
end
