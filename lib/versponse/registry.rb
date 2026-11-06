# frozen_string_literal: true

module Versponse
  # Every response class (recorded by {Base.inherited}) and every declared version name
  #
  # @api private
  module Registry
    @classes = []
    @version_names = [].freeze
    @mutex = Mutex.new

    class << self
      # @return [Array<String>] every version declared by any response class, oldest first
      attr_reader :version_names

      # Replaces a registered class with the same name, so code reloading doesn't keep stale classes.
      #
      # @param klass [Class] response class
      # @return [void]
      def add(klass)
        name = klass.name
        @mutex.synchronize do
          @classes.reject! { |registered| registered.name == name } if name
          @classes << klass
        end
      end

      # @param name [String] declared version name
      # @return [void]
      def add_version_name(name)
        @mutex.synchronize { @version_names = (@version_names | [name]).sort.freeze }
      end

      # @return [Array<Class>] every registered class, including anonymous ones
      def all
        @mutex.synchronize { @classes.dup }
      end

      # @return [Array<Class>] named classes still bound to their constant (skips stale reloaded classes)
      def classes
        all.select { |klass| live?(klass) }
      end

      private

      def live?(klass)
        klass.name && ::Object.const_defined?(klass.name) && ::Object.const_get(klass.name).equal?(klass)
      rescue NameError
        false
      end
    end
  end
end
