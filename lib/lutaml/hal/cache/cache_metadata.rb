# frozen_string_literal: true

require 'lutaml/model'

module Lutaml
  module Hal
    module Cache
      # Represents HTTP response metadata from the request that created the HAL resource
      class CacheMetadata < Lutaml::Model::Serializable
        attribute :etag, :string
        attribute :last_modified, :string
        attribute :cache_control, :string
        attribute :expires, :string
        attribute :status_code, :integer
        attribute :content_type, :string
        attribute :date, :string
        attribute :vary, :string

        # Extract metadata from HTTP response headers
        def self.from_response(response)
          headers = extract_headers(response)

          new(
            etag: headers['etag'],
            last_modified: headers['last-modified'],
            cache_control: headers['cache-control'],
            expires: headers['expires'],
            status_code: extract_status_code(response),
            content_type: headers['content-type'],
            date: headers['date'],
            vary: headers['vary']
          )
        end

        # Generate conditional request headers for cache validation
        def conditional_headers
          headers = {}
          headers['If-None-Match'] = etag if etag
          headers['If-Modified-Since'] = last_modified if last_modified
          headers
        end

        # Check if the metadata indicates the response is cacheable
        def cacheable?
          return false if cache_control&.include?('no-cache')
          return false if cache_control&.include?('no-store')
          return false if cache_control&.include?('private')

          true
        end

        # Extract TTL from cache-control header
        def max_age
          return nil unless cache_control

          match = cache_control.match(/max-age=(\d+)/)
          match ? match[1].to_i : nil
        end

        # Check if the response can be revalidated with conditional requests
        def revalidatable?
          !etag.nil? && !etag.empty? || !last_modified.nil? && !last_modified.empty?
        end

        def self.extract_headers(response)
          case response
          when Hash
            # Response is already a hash, extract headers directly
            response.select { |k, _| k.is_a?(String) && k.match?(/^[a-z-]+$/) }
          when ->(r) { r.respond_to?(:headers) }
            # Response has headers method
            response.headers.to_h
          when ->(r) { r.respond_to?(:[]) }
            # Response is hash-like, try to extract common headers
            {
              'etag' => response['etag'],
              'last-modified' => response['last-modified'],
              'cache-control' => response['cache-control'],
              'expires' => response['expires'],
              'content-type' => response['content-type'],
              'date' => response['date'],
              'vary' => response['vary']
            }.compact
          else
            {}
          end
        end

        def self.extract_status_code(response)
          case response
          when Hash
            response['status'] || response[:status] || 200
          when ->(r) { r.respond_to?(:status) }
            response.status
          when ->(r) { r.respond_to?(:code) }
            response.code.to_i
          else
            200
          end
        end
      end
    end
  end
end
