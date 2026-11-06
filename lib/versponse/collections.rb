# frozen_string_literal: true

module Versponse
  # What renders as a collection (anything with to_ary, such as an Array or an ActiveRecord relation,
  # and Sets), and rendering its items with the index in extraction errors
  #
  # @api private
  module Collections
    # @param value [Object] source
    # @return [Boolean] true when the value renders as a collection
    def self.collection?(value)
      value.respond_to?(:to_ary) || value.is_a?(::Set)
    end

    # @param value [#to_ary, Set] collection
    # @return [Array] its items
    # @raise [KeyError] for a value that isn't a collection (the plan reports it with the key path)
    def self.items(value)
      return value.to_ary if value.respond_to?(:to_ary)
      return value.to_a if value.is_a?(::Set)

      raise KeyError, "expected a collection, got #{value.class}"
    end

    # @param items [Array] items to render
    # @yieldparam item [Object] one item
    # @return [Array] the rendered items
    # @raise [Versponse::ExtractionError] with the item's index in its keys when an item fails
    def self.map(items)
      index = 0
      items.map do |item|
        rendered = yield(item)
        index += 1
        rendered
      end
    rescue ExtractionError => e
      raise ExtractionError.new(label: e.label, keys: [index.to_s, *e.keys], detail: e.detail)
    rescue NoMethodError, KeyError => e
      raise ExtractionError.new(label: "", keys: [index.to_s], detail: e.message)
    end
  end
end
