# frozen_string_literal: true

module Versponse
  class Selection
    # A selected render's expand tree node paired with its selection node. Plans and steps take it where they take an
    # Expansion, so renders without fields: pass the plain Expansion and run as before.
    #
    # @api private
    class Scope
      # @return [Versponse::Selection] selected fields of this object
      attr_reader :selection

      # @param expansion [Versponse::Expansion] expand tree node
      # @param selection [Versponse::Selection] selection node (not ALL)
      def initialize(expansion, selection)
        @expansion = expansion
        @selection = selection
        freeze
      end

      # @param key [String] output key
      # @return [Boolean] true when the association under key is expanded
      def expand?(key)
        @expansion.expand?(key)
      end

      # @param key [String] output key
      # @return [Scope, Versponse::Expansion] the child's scope, or its plain expand tree node when the key is
      #   selected whole
      def child(key)
        selection = @selection.child(key)
        selection.all? ? @expansion.child(key) : Scope.new(@expansion.child(key), selection)
      end
    end
  end
end
