# frozen_string_literal: true

module Versponse
  # Schemas of referenced classes: Versponse classes, or any class implementing the reference
  # protocol (to_ref(property:) and to_validation_schema(version:, property:)), such as verquest requests.
  # A foreign class that references back to the class being generated (A -> verquest -> A) re-enters
  # A's schema cache and raises ThreadError; such cross-gem cycles are not supported.
  #
  # @api private
  module References
    # @param klass [Object] referenced class
    # @return [Boolean] true for Versponse response classes
    def self.versponse?(klass)
      klass.is_a?(Class) && klass < Base
    end

    # @param klass [Class] referenced class
    # @param view [Symbol] view of a Versponse class
    # @param property [Symbol, nil] property of a non-Versponse class
    # @param context [Versponse::SchemaContext] schema generation context
    # @return [Hash] a $ref, or the inlined schema in validation mode
    def self.schema(klass, view:, property:, context:)
      return foreign_schema(klass, property:, context:) unless versponse?(klass)
      return {"$ref" => klass.to_ref(view:)} unless context.validation?

      context.inline([klass, view], klass.component_name(view:)) { klass.object_schema(version: context.version, view:, context:) }
    end

    # @param klass [Class] non-Versponse class implementing the protocol
    # @param property [Symbol, nil] referenced property
    # @param context [Versponse::SchemaContext] schema generation context
    # @return [Hash] a $ref, or its validation schema
    def self.foreign_schema(klass, property:, context:)
      return {"$ref" => klass.to_ref(property:)} unless context.validation?

      klass.to_validation_schema(version: context.version, property:)
    end
  end
end
