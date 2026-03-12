# frozen_string_literal: true

require_relative 'cache_metadata'

module Lutaml
  module Hal
    module Cache
      # Represents a complete cached entry with metadata and HAL resource
      class CacheEntry
        attr_accessor :url, :cached_at, :metadata, :hal_resource

        def initialize(url: nil, cached_at: nil, metadata: nil, hal_resource: nil)
          @url = url
          @cached_at = cached_at
          @metadata = metadata
          @hal_resource = hal_resource
        end

        # Create a cache entry from a URL, response, and realized HAL resource
        def self.create(url, response, hal_resource)
          new(
            url: url,
            cached_at: Time.now.to_s,
            metadata: CacheMetadata.from_response(response),
            hal_resource: hal_resource
          )
        end

        # Check if the cache entry is still valid based on TTL
        def valid?(default_ttl)
          return false unless cached_at

          cached_time = cached_at.is_a?(String) ? Time.parse(cached_at) : cached_at
          age = Time.now - cached_time
          ttl = metadata&.max_age || default_ttl

          age < ttl
        end

        # Check if the entry is expired and needs revalidation
        def expired?(default_ttl)
          !valid?(default_ttl)
        end

        # Check if the entry can be revalidated with conditional requests
        def revalidatable?
          return false unless metadata
          !!(metadata.etag || metadata.last_modified)
        end

        # Get conditional headers for revalidation
        def conditional_headers
          metadata&.conditional_headers || {}
        end

        # Check if the response is cacheable based on metadata
        def cacheable?
          metadata&.cacheable? != false
        end

        # Update the cache entry with fresh metadata (for 304 responses)
        def refresh_metadata(response)
          self.cached_at = Time.now.to_s
          self.metadata = CacheMetadata.from_response(response)
        end

        # Get cache age in seconds
        def age
          return 0 unless cached_at

          cached_time = cached_at.is_a?(String) ? Time.parse(cached_at) : cached_at
          Time.now - cached_time
        end

        # Check if entry should be served stale (useful for error scenarios)
        def serve_stale?(max_stale = nil)
          return false unless max_stale
          return false if valid?(Float::INFINITY)  # Still fresh

          cached_time = cached_at.is_a?(String) ? Time.parse(cached_at) : cached_at
          current_age = Time.now - cached_time
          ttl = metadata&.max_age || 0

          # Entry is stale if current_age > ttl
          # But we can serve it if the staleness is within the max_stale window
          staleness = current_age - ttl
          current_age > ttl && staleness < max_stale
        end
      end
    end
  end
end
