# frozen_string_literal: true

require 'lutaml/model'

module Lutaml
  module Hal
    module Cache
      class CacheMetadata < Lutaml::Model::Serializable
        attribute :etag, :string
        attribute :last_modified, :string
        attribute :cache_control, :string
        attribute :expires, :string
        attribute :status_code, :integer
        attribute :content_type, :string
        attribute :date, :string
        attribute :vary, :string

        def self.from_response(response)
          headers = ResponseAdapter.headers(response)

          new(
            etag: headers['etag'],
            last_modified: headers['last-modified'],
            cache_control: headers['cache-control'],
            expires: headers['expires'],
            status_code: ResponseAdapter.status_code(response),
            content_type: headers['content-type'],
            date: headers['date'],
            vary: headers['vary']
          )
        end

        def conditional_headers
          headers = {}
          headers['If-None-Match'] = etag if etag
          headers['If-Modified-Since'] = last_modified if last_modified
          headers
        end

        def cacheable?
          return false if cache_control&.include?('no-cache')
          return false if cache_control&.include?('no-store')
          return false if cache_control&.include?('private')

          true
        end

        def max_age
          return nil unless cache_control

          match = cache_control.match(/max-age=(\d+)/)
          match ? match[1].to_i : nil
        end

        def revalidatable?
          !!(etag && !etag.empty?) || !!(last_modified && !last_modified.empty?)
        end
      end
    end
  end
end
