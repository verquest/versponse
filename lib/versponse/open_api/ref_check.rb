# frozen_string_literal: true

module Versponse
  module OpenAPI
    # Finds local "$ref"s ("#/...") that point at nothing in a built document. Anchor references
    # ("#Name"), external references and example values are left alone.
    #
    # @api private
    module RefCheck
      # Keywords whose values are data, so a "$ref" key in them isn't a reference
      DATA_KEYWORDS = %w[example examples default const enum].freeze

      # @param document [Hash] built OpenAPI document
      # @return [Array<Hash>] errors with :pointer, :type, :message and :details
      def self.call(document)
        errors = []
        walk(document, "", document, errors)
        errors
      end

      def self.walk(value, pointer, document, errors)
        case value
        when Hash
          check(value["$ref"], pointer, document, errors) if value["$ref"].is_a?(String)
          value.each do |key, item|
            walk(item, "#{pointer}/#{escape(key)}", document, errors) unless DATA_KEYWORDS.include?(key)
          end
        when Array
          value.each_with_index { |item, index| walk(item, "#{pointer}/#{index}", document, errors) }
        end
      end

      def self.check(ref, pointer, document, errors)
        return unless ref.start_with?("#/")
        return if resolves?(document, ref)

        errors << {pointer:, type: "ref", message: "$ref #{ref} does not resolve in the document", details: {"ref" => ref}}
      end

      def self.resolves?(document, ref)
        ref.delete_prefix("#/").split("/").reduce(document) do |node, token|
          token = token.gsub("~1", "/").gsub("~0", "~")
          case node
          when Hash then node.fetch(token) { return false }
          when Array then (/\A\d+\z/.match?(token) && token.to_i < node.size) ? node[token.to_i] : (return false)
          else return false
          end
        end
        true
      end

      def self.escape(key)
        key.to_s.gsub("~", "~0").gsub("/", "~1")
      end

      private_class_method :walk, :check, :resolves?, :escape
    end
  end
end
