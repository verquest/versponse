# frozen_string_literal: true

module Versponse
  # Lets one-argument lambdas and methods be used where Versponse passes (object, context)
  #
  # @api private
  module Callable
    # Symbol procs (&:name) and C methods have unnamed parameters, and take the object only
    # even when their rest parameter would accept the context too
    #
    # @param callable [Proc, Method, #call, nil] block, lambda, method or other callable
    # @return [#call, nil] a callable that accepts (object, context)
    # @raise [Versponse::DefinitionError] for a value that isn't callable, or a lambda or method
    #   that takes neither 1 nor 2 arguments
    def self.normalize(callable)
      return if callable.nil?
      raise DefinitionError, "expected a callable (a Proc, lambda or Method), got #{callable.inspect}" unless callable.respond_to?(:call)
      return callable unless callable.respond_to?(:parameters)
      return callable if callable.is_a?(Proc) && !callable.lambda?

      params = callable.parameters
      raise DefinitionError, "callables cannot take required keyword arguments" if params.any? { |type, _| type == :keyreq }

      required = params.count { |type, _| type == :req }
      max = (params.any? { |type, _| type == :rest }) ? Float::INFINITY : required + params.count { |type, _| type == :opt }
      one = 1.between?(required, max)
      return callable if 2.between?(required, max) && !(one && params.any? { |_, name| name.nil? })
      return ->(object, _context) { callable.call(object) } if one

      raise DefinitionError, "callables take (object) or (object, context)"
    end
  end
end
