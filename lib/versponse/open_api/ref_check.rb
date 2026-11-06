# frozen_string_literal: true

module Versponse
  module OpenAPI
    # Finds local "$ref"s ("#/...") that point at nothing in a built document. Anchor references
    # ("#Name"), external references and example values are left alone.
    #
    # @api private
    module RefCheck
      # Keywords whose values are data, so a "$ref" key in them isn't a reference ("examples" too when it's
      # a schema's Array; a Hash of Example Objects is walked)
      DATA_KEYWORDS = %w[example default const enum].freeze

      # Keywords whose keys are names (a property may be called "default"), not keywords
      NAME_MAPS = %w[properties patternProperties $defs definitions dependentSchemas].freeze

      # @param document [Hash] built OpenAPI document
      # @return [Array<Hash>] errors with :pointer, :type, :message and :details
      def self.call(document)
        errors = []
        walk(document, "", document, errors)
        errors
      end

      def self.walk(value, pointer, document, errors, names: false)
        case value
        when Hash then names ? walk_names(value, pointer, document, errors) : walk_object(value, pointer, document, errors)
        when Array then value.each_with_index { |item, index| walk(item, "#{pointer}/#{index}", document, errors) }
        end
      end

      def self.walk_names(map, pointer, document, errors)
        map.each { |name, item| walk(item, "#{pointer}/#{escape(name)}", document, errors) }
      end

      def self.walk_object(object, pointer, document, errors)
        check(object["$ref"], pointer, document, errors) if object["$ref"].is_a?(String)
        check_mapping(object["discriminator"], "#{pointer}/discriminator", document, errors)
        object.each do |key, item|
          next if DATA_KEYWORDS.include?(key) || (key == "examples" && !item.is_a?(Hash))

          walk(item, "#{pointer}/#{escape(key)}", document, errors, names: NAME_MAPS.include?(key))
        end
      end

      def self.check_mapping(discriminator, pointer, document, errors)
        return unless discriminator.is_a?(Hash) && discriminator["mapping"].is_a?(Hash)

        discriminator["mapping"].each do |value, ref|
          check(ref, "#{pointer}/mapping/#{escape(value)}", document, errors) if ref.is_a?(String)
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

      private_class_method :walk, :walk_names, :walk_object, :check_mapping, :check, :resolves?, :escape
    end
  end
end
