# frozen_string_literal: true

module Lutaml
  module Hal
    module Cache
      # Simple in-memory cache store for testing and fallback scenarios.
      #
      # Thread-safe: a single mutex guards the cache and its LRU bookkeeping so
      # it can back the register cache when consumers realize links from many
      # threads (e.g. a parallel fetcher).
      class SimpleCacheStore
        attr_reader :max_size

        def initialize(max_size = 100)
          @max_size = max_size
          @cache = {}
          @access_order = []
          @mutex = Mutex.new
        end

        def get(key)
          @mutex.synchronize do
            return nil unless @cache.key?(key)

            # Update access order for LRU
            @access_order.delete(key)
            @access_order.push(key)

            @cache[key]
          end
        end

        def set(key, value)
          @mutex.synchronize do
            # Remove existing entry if present
            if @cache.key?(key)
              @access_order.delete(key)
            elsif @cache.size >= @max_size
              # Evict least recently used item
              lru_key = @access_order.shift
              @cache.delete(lru_key)
            end

            @cache[key] = value
            @access_order.push(key)
          end
        end

        def delete(key)
          @mutex.synchronize do
            @access_order.delete(key)
            @cache.delete(key)
          end
        end

        def clear
          @mutex.synchronize do
            @cache.clear
            @access_order.clear
          end
        end

        def size
          @mutex.synchronize { @cache.size }
        end

        def stats
          @mutex.synchronize do
            {
              size: @cache.size,
              max_size: @max_size,
              keys: @cache.keys
            }
          end
        end

        def cache_info
          stats
        end
      end
    end
  end
end
