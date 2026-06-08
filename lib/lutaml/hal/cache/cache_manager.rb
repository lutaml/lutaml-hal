# frozen_string_literal: true

require 'lutaml/store'

module Lutaml
  module Hal
    module Cache
      class CacheManager
        attr_reader :configuration, :cache_store

        def initialize(config = nil, client: nil)
          @client = client
          @configuration = CacheConfiguration.from_config(config)
          begin
            @configuration.validate!
          rescue ArgumentError => e
            raise ArgumentError, "Invalid cache configuration: #{e.message}"
          end
          @cache_store = create_cache_store
        end

        def get(url)
          return nil unless cache_store

          key = cache_key(url)
          raw = cache_store.get(key)
          return nil unless raw

          deserialize_entry(raw)
        end

        def set(url, response, hal_resource)
          return unless cache_store

          entry = CacheEntry.create(url, response, hal_resource)
          return unless entry.cacheable?

          key = cache_key(url)
          cache_store.set(key, entry.to_storage_h)
          entry
        end

        def conditional_request_headers(url)
          entry = get(url)
          return {} unless entry&.revalidatable?

          entry.conditional_headers
        end

        def refresh_entry(url, response)
          entry = get(url)
          return unless entry

          entry.refresh_metadata(response)
          key = cache_key(url)
          cache_store.set(key, entry.to_storage_h)
        end

        def invalidate(url)
          return unless cache_store

          key = cache_key(url)
          cache_store.delete(key)
        end

        def clear
          return unless cache_store

          cache_store.clear
        end

        def stats
          return {} unless cache_store

          cache_store.cache_info
        end

        def info
          return nil unless cache_store

          {
            adapter_type: cache_store.class.name,
            configuration: configuration,
            current_size: cache_store.size,
            stats: stats
          }
        end

        def available?
          !cache_store.nil?
        end

        private

        def create_cache_store
          store_config = @configuration.to_cache_store_config
          ::Lutaml::Store::CacheStore.new(store_config)
        rescue StandardError => e
          Hal.debug_log("Failed to create cache store: #{e.message}")
          nil
        end

        def cache_key(url)
          "hal_resource:#{canonical_url(url)}"
        end

        def canonical_url(url)
          url = url.to_s
          return url if url.start_with?('http')
          return url unless @client&.api_url

          "#{@client.api_url}#{url}"
        end

        def deserialize_entry(raw)
          case raw
          when CacheEntry
            raw
          when Hash
            CacheEntry.from_storage_h(raw) if CacheEntry.storage_format?(raw)
          end
        end
      end
    end
  end
end
