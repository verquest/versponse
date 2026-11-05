# frozen_string_literal: true

module Versponse
  # Thread-safe compute-once cache. Reads take no lock: the store is a frozen Hash replaced on write.
  #
  # A block passed to {#fetch} must not fetch from the same cache (the lock is not reentrant).
  #
  # @api private
  class Cache
    # @return [Cache] an empty cache
    def initialize
      @store = {}.freeze
      @mutex = Mutex.new
    end

    # @param key [Object] cache key
    # @yieldreturn [Object] value computed when the key is missing
    # @return [Object] the cached value
    def fetch(key)
      @store.fetch(key) do
        @mutex.synchronize do
          @store.fetch(key) do
            value = yield
            @store = @store.merge(key => value).freeze
            value
          end
        end
      end
    end

    # @return [void]
    def clear
      @mutex.synchronize { @store = {}.freeze }
    end
  end
end
