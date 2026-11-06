# frozen_string_literal: true

module Versponse
  # Thread-safe compute-once cache. Reads take no lock: the store is a frozen Hash replaced on write.
  #
  # A block passed to {#fetch} must not fetch from the same cache (the lock is not reentrant).
  # With a limit, keys past it are computed on every fetch instead of stored, for keys that come from requests.
  #
  # @api private
  class Cache
    # @param limit [Integer, nil] most keys stored, nil for no limit
    # @return [Cache] an empty cache
    def initialize(limit: nil)
      @store = {}.freeze
      @mutex = Mutex.new
      @limit = limit
    end

    # @param key [Object] cache key
    # @yieldreturn [Object] value computed when the key is missing
    # @return [Object] the cached value
    def fetch(key)
      @store.fetch(key) do
        return yield if @limit && @store.size >= @limit

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
