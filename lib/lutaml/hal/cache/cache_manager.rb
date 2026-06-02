# frozen_string_literal: true

require_relative 'cache_configuration'
require_relative 'cache_entry'
require_relative 'cache_metadata'
require_relative 'simple_cache_store'

# Try to require lutaml-store. Requiring the entry point (rather than the
# individual files) sets up the autoloads it relies on internally, e.g.
# Lutaml::Store::HttpCacheConfig referenced from HttpCache#initialize.
begin
  require 'lutaml/store'
  CACHE_STORE_AVAILABLE = true
rescue LoadError
  CACHE_STORE_AVAILABLE = false
end

module Lutaml
  module Hal
    module Cache
      # Manages all cache operations with a clean, unified interface
      class CacheManager
        attr_reader :configuration, :cache_store

        def initialize(config = nil)
          @configuration = CacheConfiguration.from_config(config)
          begin
            @configuration.validate!
          rescue ArgumentError => e
            raise ArgumentError, "Invalid cache configuration: #{e.message}"
          end
          @cache_store = create_cache_store
        end

        # Get a cache entry by URL
        def get(url)
          return nil unless cache_store

          key = cache_key(url)

          if http_aware_cache?
            get_from_http_cache(url, key)
          else
            get_from_basic_cache(key)
          end
        end

        # Store a cache entry
        def set(url, response, hal_resource)
          return unless cache_store

          entry = CacheEntry.create(url, response, hal_resource)
          return unless entry.cacheable?

          key = cache_key(url)

          if http_aware_cache?
            set_in_http_cache(key, entry, response)
          else
            set_in_basic_cache(key, entry)
          end

          entry
        end

        # Make a conditional request using cached metadata
        def conditional_request_headers(url)
          entry = get(url)
          return {} unless entry&.revalidatable?

          entry.conditional_headers
        end

        # Update cache entry after a 304 Not Modified response
        def refresh_entry(url, response)
          entry = get(url)
          return unless entry

          entry.refresh_metadata(response)
          set_refreshed_entry(url, entry)
        end

        # Remove a specific cache entry
        def invalidate(url)
          return unless cache_store

          key = cache_key(url)
          cache_store.delete(key)
        end

        # Clear all cache entries
        def clear
          return unless cache_store

          cache_store.clear
        end

        # Get cache statistics
        def stats
          return {} unless cache_store

          if cache_store.respond_to?(:cache_info)
            cache_store.cache_info
          elsif cache_store.respond_to?(:stats)
            cache_store.stats
          else
            {}
          end
        end

        # Get cache information
        def info
          return nil unless cache_store

          {
            adapter_type: cache_store.class.name,
            configuration: configuration,
            current_size: cache_store.respond_to?(:size) ? cache_store.size : 'unknown',
            stats: stats
          }
        end

        # Check if cache is available and configured
        def available?
          !cache_store.nil?
        end

        # Check if using HTTP-aware cache
        def http_aware_cache?
          configuration.http_aware? && cache_store.respond_to?(:fetch)
        end

        private

        def create_cache_store
          # The cache stores realized HAL models directly, which requires an
          # object-preserving in-memory store: lutaml-store's CacheStore
          # serializes entries to JSON and cannot round-trip a live model.
          # Conditional requests (ETag / Last-Modified) are still driven from
          # each entry's stored metadata, independent of the backend.
          #
          # NOTE: Backing the HTTP-aware mode with lutaml-store's HttpCache
          # response cache is deferred until realized models can be
          # reconstructed from a cached response (requires the resource class);
          # the create_http_cache / *_http_cache helpers remain as scaffolding.
          create_simple_cache
        rescue => e
          Lutaml::Hal.debug_log("Failed to create cache store: #{e.message}")
          create_simple_cache
        end

        def create_http_cache
          return nil unless defined?(::Lutaml::Store::HttpCache)

          ::Lutaml::Store::HttpCache.new(configuration.http_cache_config)
        end

        def create_basic_cache
          return nil unless defined?(::Lutaml::Store::CacheStore)

          ::Lutaml::Store::CacheStore.new(configuration.basic_cache_config)
        end

        def create_simple_cache
          SimpleCacheStore.new(configuration.effective_max_size)
        end

        def cache_key(url)
          "hal_resource:#{url}"
        end

        def get_from_http_cache(url, key)
          # HTTP cache handles conditional requests internally
          cached_response = cache_store.get(key)
          return nil unless cached_response

          # Convert HTTP cache response back to CacheEntry
          convert_http_response_to_entry(url, cached_response)
        end

        def get_from_basic_cache(key)
          cached_data = cache_store.get(key)
          return nil unless cached_data

          # Basic cache stores CacheEntry directly
          case cached_data
          when CacheEntry
            cached_data.valid?(configuration.effective_ttl) ? cached_data : nil
          when Hash
            # Legacy format support
            convert_legacy_cache_data(cached_data)
          else
            nil
          end
        end

        def set_in_http_cache(key, entry, response)
          # Convert CacheEntry to HTTP cache format
          http_response = convert_entry_to_http_response(entry, response)
          cache_store.set(key, http_response)
        end

        def set_in_basic_cache(key, entry)
          cache_store.set(key, entry)
        end

        def set_refreshed_entry(url, entry)
          key = cache_key(url)

          if http_aware_cache?
            # For HTTP cache, we need to update the stored response
            http_response = convert_entry_to_http_response(entry, nil)
            cache_store.set(key, http_response)
          else
            cache_store.set(key, entry)
          end
        end

        def convert_http_response_to_entry(url, http_response)
          # Extract HAL resource and metadata from HTTP cache response
          body = http_response[:body] || http_response['body']
          headers = http_response[:headers] || http_response['headers'] || {}

          # Parse the body back to get the HAL resource
          # Note: This is a simplified conversion - in practice, we might need
          # to store the HAL resource separately or use serialization
          hal_resource = parse_hal_resource_from_body(body)

          CacheEntry.new(
            url: url,
            cached_at: Time.now, # HTTP cache manages its own timestamps
            metadata: CacheMetadata.from_response(headers),
            hal_resource: hal_resource
          )
        end

        def convert_entry_to_http_response(entry, original_response)
          {
            status_code: entry.metadata&.status_code || 200,
            headers: extract_headers_from_metadata(entry.metadata),
            body: serialize_hal_resource(entry.hal_resource)
          }
        end

        def convert_legacy_cache_data(cached_data)
          # Support for legacy cache format
          return nil unless cached_data[:realized_model] && cached_data[:cached_at]

          CacheEntry.new(
            url: cached_data[:url],
            cached_at: cached_data[:cached_at],
            metadata: create_metadata_from_legacy(cached_data),
            hal_resource: cached_data[:realized_model]
          )
        end

        def create_metadata_from_legacy(cached_data)
          CacheMetadata.new(
            etag: cached_data[:etag],
            last_modified: cached_data[:last_modified],
            status_code: 200
          )
        end

        def extract_headers_from_metadata(metadata)
          return {} unless metadata

          {
            'etag' => metadata.etag,
            'last-modified' => metadata.last_modified,
            'cache-control' => metadata.cache_control,
            'expires' => metadata.expires,
            'content-type' => metadata.content_type,
            'date' => metadata.date,
            'vary' => metadata.vary
          }.compact
        end

        def parse_hal_resource_from_body(body)
          # This is a placeholder - in practice, we might need to store
          # the HAL resource class information to properly deserialize
          case body
          when String
            JSON.parse(body)
          else
            body
          end
        rescue JSON::ParserError
          body
        end

        def serialize_hal_resource(hal_resource)
          # Serialize HAL resource for storage
          case hal_resource
          when ->(r) { r.respond_to?(:to_json) }
            hal_resource.to_json
          else
            hal_resource.to_s
          end
        end
      end
    end
  end
end
