# frozen_string_literal: true

module Versponse
  # Tree of the fields a render selects (serialize fields:), built from dotted paths. A node selects some keys of
  # one object; a key selected whole (or with ".*") has the ALL node. Each node memoizes the step indexes of each
  # plan it meets; trees are cached per class, so the memo is thread-safe.
  #
  # @api private
  class Selection
    # @param paths [Array<String, Symbol>, nil] validated paths
    # @return [Selection] ALL for none, or with a root "*"
    def self.build(paths)
      paths = Array(paths).map(&:to_s)
      return ALL if paths.empty? || paths.include?("*")

      paths = paths.map { |path| path.delete_suffix(".*") }.uniq.sort
      tree = {}
      paths.each { |path| add(tree, path.split(".")) }
      from_hash(tree, signature: paths.join("\n").freeze)
    end

    # @param tree [Hash{String => Hash, Symbol}] node being built (:all for a key selected whole)
    # @param segments [Array<String>] path segments
    # @return [void]
    def self.add(tree, segments)
      *parents, leaf = segments
      node = parents.reduce(tree) do |current, segment|
        child = current[segment]
        break if child == :all

        child || (current[segment] = {})
      end
      node[leaf] = :all if node
    end

    # @param tree [Hash{String => Hash, Symbol}] built tree
    # @param signature [String, nil] the root's sorted paths
    # @return [Selection] node
    def self.from_hash(tree, signature: nil)
      new(tree.transform_values { |child| (child == :all) ? ALL : from_hash(child) }.freeze, signature:)
    end
    private_class_method :add, :from_hash

    # @return [String, nil] sorted paths of a root selection, for cache keys
    attr_reader :signature

    # @param children [Hash{String => Selection}, nil] selected keys and their nodes; nil selects everything
    # @param signature [String, nil] sorted paths of a root selection
    def initialize(children = nil, signature: nil)
      @children = children
      @signature = signature
      @indexes = Cache.new unless children.nil?
    end

    # @return [Boolean] true when every key is selected
    def all?
      @children.nil?
    end

    # @param key [String] output key
    # @return [Boolean] true when the key is selected
    def selected?(key)
      all? || @children.key?(key)
    end

    # @param key [String] output key
    # @return [Selection] the key's node: ALL for a key selected whole, under ALL, or not selected (a plan only asks
    #   for keys it renders)
    def child(key)
      all? ? ALL : @children.fetch(key, ALL)
    end

    # @param plan [#steps, #always] plan rendered at this node
    # @return [Array<Integer>] frozen indexes of the plan's selected and always-emitted steps, memoized per plan
    def indexes_for(plan)
      @indexes[plan] || @indexes.fetch(plan) do
        plan.steps.each_index.select do |index|
          key = plan.steps[index].key
          @children.key?(key) || plan.always.include?(key)
        end.freeze
      end
    end

    # Everything selected: today's output
    ALL = new.freeze
  end
end
