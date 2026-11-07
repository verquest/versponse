# frozen_string_literal: true

module Versponse
  module Properties
    # The unnamed one_of inside a collection block: types each item of the collection
    #
    # @api private
    class ItemOneOf < OneOf
      # @return [Boolean] false: the collection's context: covers the items
      def self.context_option? = false

      # @param _block [Proc] unused
      # @raise [Versponse::DefinitionError] always, the collection owns the value source
      def source=(_block)
        raise DefinitionError, "#{key}: source belongs to the collection, declare it outside the unnamed one_of"
      end
    end
  end
end
