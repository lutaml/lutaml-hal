# frozen_string_literal: true

module Lutaml
  module Hal
    module Cache
      # Simple in-memory cache store for testing and fallback scenarios
      class SimpleCacheStore
        attr_reader :max_size

        def initialize(max_size = 100)
          @max_size = max_size
          @cache = {}
          @access_order = []
        end

        def get(key)
          return nil unless @cache.key?(key)

          # Update access order for LRU
          @access_order.delete(key)
          @access_order.push(key)

          @cache[key]
        end

        def set(key, value)
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

        def delete(key)
          @access_order.delete(key)
          @cache.delete(key)
        end

        def clear
          @cache.clear
          @access_order.clear
        end

        def size
          @cache.size
        end

        def stats
          {
            size: @cache.size,
            max_size: @max_size,
            keys: @cache.keys
          }
        end

        def cache_info
          stats
        end
      end
    end
  end
end
