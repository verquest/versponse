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
      # @return [Array<Array(Array<String>, Array<Class>)>] entries of the child properties
      def expandable_entries(version:, prefix:, stack:)
        child_properties.flat_map { |property| property.expandable_entries(version:, prefix: prefix + [key], stack:) }
      end

      # @param version [String] canonical version name
      # @return [Array<Versponse::Properties::Base>] the child properties
      def path_children(version)
        child_properties
      end

      # @return [Array<Array(Class, Symbol, String)>] the reference targets of the child properties
      def reference_targets
        child_properties.flat_map(&:reference_targets)
      end

      private

      def child_properties
        @properties&.values || []
      end

      def inline_plan(version, formatters, policies)
        properties = FieldOrder.call(child_properties)
        Plan.new(label: key, steps: properties.map { |property| property.step(version:, formatters:, policies:) },
          recoveries: ErrorPolicy.recoveries(properties, policies, version))
      end

      def inline_schema(context)
        ObjectSchema.build(FieldOrder.call(child_properties), context)
      end
    end
  end
end
