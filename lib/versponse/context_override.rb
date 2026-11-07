# frozen_string_literal: true

module Versponse
  # The context a nested property's subtree renders with: a Hash merged over the parent context, or a callable
  # returning the child context
  #
  # @api private
  module ContextOverride
    # @param option [Hash, #call, nil] the property's context: option
    # @param key [String] property key, for error messages
    # @return [Merge, Call, nil] the override, nil without the option
    # @raise [Versponse::DefinitionError] for any other value, or a callable taking neither (object) nor (object, context)
    def self.build(option, key:)
      return if option.nil?
      return Merge.new(DeepFreeze.call(option)) if option.is_a?(Hash)
      raise DefinitionError, "#{key}: context: must be a Hash or respond to call" unless option.respond_to?(:call)

      begin
        Call.new(Callable.normalize(option))
      rescue DefinitionError => e
        raise DefinitionError, "#{key}: context: #{e.message}"
      end
    end
  end
end
