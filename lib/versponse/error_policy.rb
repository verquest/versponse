# frozen_string_literal: true

module Versponse
  # What happens when a property fails to render: :raise, :nullify, :omit, or a handler called with
  # (error, object, key, context) whose return value is written
  #
  # @api private
  module ErrorPolicy
    # Policies given as Symbols
    POLICIES = %i[raise nullify omit].freeze

    # Arguments a handler is called with
    HANDLER_ARGUMENTS = 4

    # Instance variable marking an error raised inside a child plan
    NESTED = :@versponse_nested_failure

    # Instance variable marking an error no policy recovers (one raised by the on_recovered_error hook)
    UNRECOVERABLE = :@versponse_unrecoverable

    # @param policy [Object] a policy as given
    # @return [Boolean] true for one of {POLICIES} or a callable taking (error, object, key, context)
    def self.valid?(policy)
      POLICIES.include?(policy) || Callable.accepts?(policy, HANDLER_ARGUMENTS)
    end

    # A frozen error can't be marked, so a class-level or config-level policy may recover it when it comes from a
    # child plan
    #
    # @param error [StandardError] error leaving a child plan
    # @return [void]
    def self.mark_nested!(error)
      error.instance_variable_set(NESTED, true) unless error.frozen?
    end

    # @param error [StandardError] error
    # @return [Boolean] true when it was raised inside a child plan
    def self.nested?(error)
      error.instance_variable_defined?(NESTED)
    end

    # @param error [StandardError] error raised by the on_recovered_error hook
    # @return [void]
    def self.mark_unrecoverable!(error)
      error.instance_variable_set(UNRECOVERABLE, true) unless error.frozen?
    end

    # @param error [StandardError] error
    # @return [Boolean] true when no policy may recover it
    def self.unrecoverable?(error)
      error.instance_variable_defined?(UNRECOVERABLE)
    end

    # @param properties [Array<Versponse::Properties::Base>] a plan's properties, in step order
    # @param policies [Versponse::ClassPolicies] the compiling class's settings
    # @param version [String] canonical version name, to find what a reference property: reuses
    # @return [Array<Recovery, nil>, nil] a recovery per step, nil when no step has one
    def self.recoveries(properties, policies, version)
      list = properties.map { |property| resolve(property, property.path_target(version), policies) }
      list.any? ? list.freeze : nil
    end

    # The property's own policy (or the reused property's), else the first of the class's and config.on_error that
    # fits what it renders (a :nullify only fits nullable properties, an :omit only conditional ones); :raise stops
    # the search
    #
    # @param property [Versponse::Properties::Base] property as declared in the plan
    # @param target [Versponse::Properties::Base] what it renders: itself, or the copy a reference property: reuses
    # @param policies [Versponse::ClassPolicies] the compiling class's settings
    # @return [Recovery, nil] nil when the property raises
    def self.resolve(property, target, policies)
      own = property.on_error || target.on_error
      return (Recovery.new(own, key: property.key, response: policies.response, explicit: true) unless own == :raise) if own

      [policies.on_error, Versponse.configuration.on_error].each do |level|
        next if level.nil?
        return nil if level == :raise
        return Recovery.new(level, key: property.key, response: policies.response, explicit: false) if fits?(level, target)
      end
      nil
    end

    # @param policy [Symbol, #call] policy
    # @param property [Versponse::Properties::Base] property
    # @return [Boolean] true when the policy keeps the property's output within its schema
    def self.fits?(policy, property)
      case policy
      when :nullify then property.nullable?
      when :omit then property.conditional?
      else true
      end
    end
  end
end
