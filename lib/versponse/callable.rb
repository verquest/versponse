# frozen_string_literal: true

module Versponse
  # Lets one-argument lambdas and methods be used where Versponse passes (object, context)
  #
  # @api private
  module Callable
    # @param callable [Proc, Method, #call, nil] block, lambda, method or other callable
    # @return [#call, nil] a callable that accepts (object, context)
    # @raise [Versponse::DefinitionError] for a lambda or method that takes neither 1 nor 2 arguments
    def self.normalize(callable)
      return callable unless callable.respond_to?(:parameters)
      return callable if callable.is_a?(Proc) && !callable.lambda?

      params = callable.parameters
      raise DefinitionError, "callables cannot take required keyword arguments" if params.any? { |type, _| type == :keyreq }

      required = params.count { |type, _| type == :req }
      max = (params.any? { |type, _| type == :rest }) ? Float::INFINITY : required + params.count { |type, _| type == :opt }
      return callable if 2.between?(required, max)
      return ->(object, _context) { callable.call(object) } if 1.between?(required, max)

      raise DefinitionError, "callables take (object) or (object, context)"
    end
  end
end
