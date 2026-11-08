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
      return callable if callable.is_a?(Proc) && !callable.lambda?

      params = (callable.respond_to?(:parameters) ? callable : call_method(callable)).parameters
      raise DefinitionError, "callables cannot take required keyword arguments" if params.any? { |type, _| type == :keyreq }

      required = params.count { |type, _| type == :req }
      max = (params.any? { |type, _| type == :rest }) ? Float::INFINITY : required + params.count { |type, _| type == :opt }
      one = 1.between?(required, max)
      return callable if 2.between?(required, max) && !(one && params.any? { |_, name| name.nil? })
      return ->(object, _context) { callable.call(object) } if one

      raise DefinitionError, "callables take (object) or (object, context)"
    end

    # Lambdas, Methods and other objects' call methods check their arity, so one that can't take the arguments fails
    # when it's declared, not on a render; procs are taken as they are
    #
    # @param callable [Object] value to check
    # @param count [Integer] positional arguments Versponse passes
    # @return [Boolean] true when callable responds to call and, unless it is a proc, takes count positional
    #   arguments and no required keywords
    def self.accepts?(callable, count)
      return false unless callable.respond_to?(:call)
      return true if callable.is_a?(Proc) && !callable.lambda?

      types = parameters(callable)&.map(&:first)
      return true if types.nil?

      required = types.count(:req)
      max = types.include?(:rest) ? Float::INFINITY : required + types.count(:opt)
      count.between?(required, max) && !types.include?(:keyreq)
    end

    # @param callable [#call] lambda, Method or object
    # @return [Array<Array(Symbol, Symbol)>, nil] its call's parameters, nil when respond_to? answers for a call
    #   method Ruby can't find
    def self.parameters(callable)
      (callable.is_a?(Proc) || callable.is_a?(Method)) ? callable.parameters : call_method(callable).parameters
    rescue NameError
      nil
    end
    private_class_method :parameters

    # Kernel#method, so an object with its own #method (a Struct member, a request) still answers
    #
    # @param callable [#call] object
    # @return [Method] its call method
    def self.call_method(callable)
      KERNEL_METHOD.bind_call(callable, :call)
    end
    private_class_method :call_method

    # Kernel#method, unbound
    KERNEL_METHOD = Kernel.instance_method(:method)
    private_constant :KERNEL_METHOD
  end
end
