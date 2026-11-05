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

      # @param version [String] canonical version name
      # @param prefix [Array<String>] output keys leading to this container
      # @param stack [Array<Array(Class, Symbol)>] classes and views being walked
      # @return [Array<Array<String>>] expandable paths of the child properties
      def expandable_paths(version:, prefix:, stack:)
        child_properties.flat_map { |property| property.expandable_paths(version:, prefix: prefix + [key], stack:) }
      end

      # @param version [String] canonical version name
      # @return [Array<Versponse::Properties::Base>] the child properties
      def path_children(version)
        child_properties
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
