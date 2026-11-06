# frozen_string_literal: true

module Versponse
  # Every response class (recorded by {Base.inherited}) and every declared version name
  #
  # @api private
  module Registry
    @classes = []
    @version_names = [].freeze
    @range_maxes = [].freeze
    @after_max = {}.freeze
    @mutex = Mutex.new

    class << self
      # @return [Array<String>] every version declared by any response class, plus every
      #   supported_versions bound, oldest first
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
        @mutex.synchronize do
          @version_names = (@version_names | [name]).sort.freeze
          @after_max = {}.freeze
        end
      end

      # Registers a supported_versions range, so canonical names never cross its bounds
      #
      # @param range [Versponse::SupportedVersions] declared range
      # @return [void]
      def add_range(range)
        [range.min, range.max].compact.each { |name| add_version_name(name) }
        @mutex.synchronize { @range_maxes = (@range_maxes | [range.max]).freeze } if range.max
      end

      # Maps a requested version to the closest earlier registered name, so arbitrary client-sent
      # strings can't grow the caches. Every declared version and supported_versions bound is
      # registered, so two requests with the same canonical name resolve alike in every class.
      # A request strictly after a max maps to the first such request seen instead of the max,
      # so it stays outside that range.
      #
      # @param name [String] requested version
      # @return [String] canonical version name, or name itself when it precedes every registered one
      def canonical(name)
        closest = Versponse.configuration.version_resolver.call(name, @version_names)
        return name if closest.nil?
        return closest if closest == name || !@range_maxes.include?(closest)

        @after_max[closest] || @mutex.synchronize do
          @after_max[closest] || (@after_max = @after_max.merge(closest => name).freeze)[closest]
        end
      end

      # Forgets the representatives of requests after a max, which depend on the version resolver
      #
      # @return [void]
      def clear_canonical
        @mutex.synchronize { @after_max = {}.freeze }
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
