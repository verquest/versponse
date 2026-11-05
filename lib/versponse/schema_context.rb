# frozen_string_literal: true

module Versponse
  # State of one schema generation. In validation mode referenced classes are inlined.
  # A class that recurses into itself gets "$anchor": "<Name>" and is referenced as "#<Name>".
  # Anchors (unlike "#/$defs/..." pointers) still resolve when the schema is embedded in
  # another document, for example by verquest. Anchor names are unique within one generated
  # schema only; keep component names unique across classes when several are embedded together.
  #
  # @api private
  class SchemaContext
    # @return [String] requested version name
    attr_reader :version

    # @param version [String] requested version name
    # @param validation [Boolean] true to inline references
    def initialize(version:, validation:)
      @version = version
      @validation = validation
      @stack = []
      @recursive = {}
      @anchored = {}
      @anchors = {}
    end

    # @return [Boolean] true when references are inlined
    def validation?
      @validation
    end

    # @param identity [Object] what is being inlined, e.g. [klass, view]; two classes can share a component name
    # @param name [String] component name, used for the anchor
    # @yieldreturn [Hash] the component schema
    # @return [Hash] the schema, or an anchor reference when the identity is recursive
    def inline(identity, name)
      return anchor_ref(identity, name) if @anchored[identity]

      if @stack.include?(identity)
        @recursive[identity] = true
        return anchor_ref(identity, name)
      end

      @stack.push(identity)
      schema = yield
      @stack.pop
      return schema unless @recursive[identity]

      @anchored[identity] = true
      schema.merge("$anchor" => anchor_name(identity, name))
    end

    private

    def anchor_ref(identity, name)
      {"$ref" => "##{anchor_name(identity, name)}"}
    end

    def anchor_name(identity, name)
      @anchors[identity] ||= begin
        base = name.to_s.empty? ? "Anonymous" : name
        candidate = base
        suffix = 1
        candidate = "#{base}#{suffix += 1}" while @anchors.value?(candidate)
        candidate
      end
    end
  end
end
