# frozen_string_literal: true

module Versponse
  # Class-level settings a property needs when its step is compiled: the response class (for reports), its
  # on_nil and its on_error
  #
  # @api private
  ClassPolicies = Data.define(:response, :on_nil, :on_error)

  # Reopened for the constant (RuboCop's Style/DataInheritance rules out subclassing Data.define)
  class ClassPolicies
    # Settings of no class: steps compiled outside a response class
    NONE = new(response: nil, on_nil: nil, on_error: nil)
  end
end
