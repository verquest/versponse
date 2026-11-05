# frozen_string_literal: true

module Versponse
  module Properties
    # Child properties of an inline object or collection
    #
    # @api private
    module Container
      # @param property [Versponse::Properties::Base] child property
      # @return [Versponse::Properties::Base] the property
      def add(property)
        (@properties ||= {})[property.key] = property
      end

      private

      def child_properties
        @properties&.values || []
      end

      def inline_plan(version)
        Plan.new(label: key, steps: child_properties.map { |property| property.step(version:) })
      end

      def inline_schema(context)
        ObjectSchema.build(child_properties, context)
      end
    end
  end
end
