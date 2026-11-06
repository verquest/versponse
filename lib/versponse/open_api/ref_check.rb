# frozen_string_literal: true

module Versponse
  module OpenAPI
    # Finds local "$ref"s ("#/...") that point at nothing in a built document. Anchor references
    # ("#Name"), external references and example values are left alone.
    #
    # @api private
    module RefCheck
      # Keywords whose values are data inside a Schema Object, so a "$ref" key in them isn't a reference ("examples"
      # too when it's a schema's Array). Outside schemas only "example" is data: "default" is a response there.
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

      # schema: true inside a Schema Object (below a "schema" key or a components/schemas entry)
      def self.walk(value, pointer, document, errors, names: false, schema: false)
        case value
        when Hash then names ? walk_names(value, pointer, document, errors, schema:) : walk_object(value, pointer, document, errors, schema:)
        when Array then value.each_with_index { |item, index| walk(item, "#{pointer}/#{index}", document, errors, schema:) }
        end
      end

      def self.walk_names(map, pointer, document, errors, schema:)
        map.each { |name, item| walk(item, "#{pointer}/#{escape(name)}", document, errors, schema:) }
      end

      def self.walk_object(object, pointer, document, errors, schema:)
        check(object["$ref"], pointer, document, errors) if object["$ref"].is_a?(String)
        check_mapping(object["discriminator"], "#{pointer}/discriminator", document, errors)
        object.each do |key, item|
          next if data?(key, item, schema:)

          components = key == "schemas" && pointer == "/components"
          walk(item, "#{pointer}/#{escape(key)}", document, errors,
            names: components || (schema && NAME_MAPS.include?(key)), schema: schema || components || key == "schema")
        end
      end

      def self.data?(key, item, schema:)
        return key == "example" unless schema

        DATA_KEYWORDS.include?(key) || (key == "examples" && !item.is_a?(Hash))
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

      private_class_method :walk, :walk_names, :walk_object, :data?, :check_mapping, :check, :resolves?, :escape
    end
  end
end
