# frozen_string_literal: true

module Versponse
  # Fast checks compiled from validation schemas. They only answer "valid?"; json_schemer stays
  # the authority for errors and for schemas the compiler doesn't support.
  #
  # @api private
  module Validator
  end
end
