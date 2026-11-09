# frozen_string_literal: true

module Versponse
  # root:/meta: wrapping of rendered output and its schema
  #
  # @api private
  module Wrapper
    # @param meta [Object, nil] meta: given for a wrapper schema
    # @return [void]
    # @raise [Versponse::DefinitionError] when meta isn't a class with a $ref, such as the Hash serialize takes
    def self.check_meta!(meta)
      return if meta.nil? || meta.respond_to?(:to_ref)

      raise DefinitionError, %(meta: takes a response class, whose $ref describes "meta"; serialize(meta:) takes the Hash)
    end

    # The envelope is strict (additionalProperties: false) whatever config.default_additional_properties says
    #
    # @param klass [Class] response class
    # @param view [Symbol] view name
    # @param root [String, Symbol] key holding the response
    # @param meta [Class, nil] class whose $ref describes "meta"
    # @param collection [Boolean] the root key holds an array
    # @return [Hash] wrapper schema
    def self.schema(klass, view:, root:, meta:, collection:)
      item = {"$ref" => klass.to_ref(view:)}
      properties = {root.to_s => collection ? {"type" => "array", "items" => item} : item}
      properties["meta"] = {"$ref" => meta.to_ref} if meta
      {"type" => "object", "required" => properties.keys, "properties" => properties, "additionalProperties" => false}
    end

    # @param data [Hash, Array<Hash>] rendered output
    # @param root [String, Symbol, nil] wraps data under this key
    # @param meta [Hash, nil] added under "meta" with String keys
    # @return [Hash, Array<Hash>] data, or the wrapper Hash
    def self.wrap(data, root:, meta:)
      return data if root.nil?

      wrapped = {root.to_s => data}
      wrapped["meta"] = string_keys(meta) if meta
      wrapped
    end

    def self.string_keys(value)
      case value
      when Hash then value.to_h { |key, item| [key.to_s, string_keys(item)] }
      when Array then value.map { |item| string_keys(item) }
      else value
      end
    end
    private_class_method :string_keys
  end
end
