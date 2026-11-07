# frozen_string_literal: true

module Versponse
  # A validation schema for a selected render: walking the schema with the selection, each object schema at a
  # selected node requires only the selected keys. Properties stay, so emitted values are still checked.
  #
  # Recursive classes are inlined once with an anchor and referenced below it. A reference met under a selection is
  # replaced by the pruned anchored schema. Pruned copies drop the anchor, and the untouched anchored originals go
  # under the definitions keyword, so references at fully selected nodes still resolve to the full shape.
  #
  # @api private
  module SelectionSchema
    # Prefix of the definitions holding the original anchored schemas
    DEFINITION_PREFIX = "versponse_"

    # @param schema [Hash] validation schema
    # @param selection [Versponse::Selection] the render's selection
    # @return [Hash] the pruned copy, or the schema itself for ALL
    def self.call(schema, selection)
      return schema if selection.all? || !schema.is_a?(Hash)

      anchors = {}
      collect_anchors(schema, anchors)
      pruned = prune(schema, selection, anchors)
      return pruned if anchors.empty?

      keyword = definitions_keyword
      pruned.merge(keyword => (pruned[keyword] || {}).merge(anchors.transform_keys { |name| "#{DEFINITION_PREFIX}#{name}" }))
    end

    # @param schema [Object] (sub)schema
    # @param selection [Versponse::Selection] node for the instance this schema describes
    # @param anchors [Hash{String => Hash}] anchored schemas by name
    # @return [Object] the pruned copy
    def self.prune(schema, selection, anchors)
      return schema if selection.all? || !schema.is_a?(Hash)

      target = anchors[ref_name(schema)]
      return prune(target, selection, anchors) if target

      pruned = schema.except(anchor_keyword)
      %w[anyOf allOf].each { |keyword| pruned[keyword] = schema[keyword].map { |branch| prune(branch, selection, anchors) } if schema[keyword].is_a?(::Array) }
      if schema["oneOf"].is_a?(::Array)
        # Pruned variants can overlap; the render already picked one with match:, so any of them passing is enough
        pruned.delete("oneOf")
        pruned["allOf"] = [*pruned["allOf"], {"anyOf" => schema["oneOf"].map { |branch| prune(branch, selection, anchors) }}]
      end
      pruned["items"] = prune(schema["items"], selection, anchors) if schema["items"].is_a?(Hash)
      return pruned unless schema["properties"].is_a?(Hash)

      pruned["properties"] = schema["properties"].to_h do |key, property|
        [key, selection.selected?(key) ? prune(property, selection.child(key), anchors) : property]
      end
      pruned["required"] = schema["required"].select { |key| selection.selected?(key) } if schema["required"].is_a?(::Array)
      pruned
    end

    # @param schema [Object] (sub)schema
    # @param anchors [Hash{String => Hash}] filled with anchored schemas by name
    # @return [void]
    def self.collect_anchors(schema, anchors)
      case schema
      when Hash
        name = anchor_name(schema)
        anchors[name] = schema if name
        schema.each_value { |value| collect_anchors(value, anchors) }
      when ::Array then schema.each { |value| collect_anchors(value, anchors) }
      end
    end

    # @return [String] "$anchor", or "$id"/"id" for JSON Schema versions before 2019-09
    def self.anchor_keyword
      Versponse.configuration.anchor("x").keys.first
    end

    # @return [String] "$defs", or "definitions" for JSON Schema versions before 2019-09
    def self.definitions_keyword
      (anchor_keyword == "$anchor") ? "$defs" : "definitions"
    end

    # @param schema [Hash] (sub)schema
    # @return [String, nil] the name it is anchored under
    def self.anchor_name(schema)
      value = schema[anchor_keyword]
      return unless value.is_a?(String)

      (anchor_keyword == "$anchor") ? value : value.delete_prefix("#")
    end

    # @param schema [Hash] (sub)schema
    # @return [String, nil] the anchor a "#Name" $ref points at
    def self.ref_name(schema)
      ref = schema["$ref"]
      ref.delete_prefix("#") if ref.is_a?(String) && ref.start_with?("#") && !ref.start_with?("#/")
    end
    private_class_method :prune, :collect_anchors, :anchor_keyword, :definitions_keyword, :anchor_name, :ref_name
  end
end
