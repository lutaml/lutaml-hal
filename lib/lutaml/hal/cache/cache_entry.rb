# frozen_string_literal: true

require 'json'
require 'time'

module Lutaml
  module Hal
    module Cache
      class CacheEntry
        attr_accessor :url, :cached_at, :metadata, :hal_resource

        def initialize(url: nil, cached_at: nil, metadata: nil, hal_resource: nil)
          @url = url
          @cached_at = cached_at
          @metadata = metadata
          @hal_resource = hal_resource
        end

        def to_storage_h
          {
            'url' => url,
            'cached_at' => cached_at,
            'metadata' => metadata&.to_json,
            'model_class' => hal_resource&.class&.name,
            'model' => hal_resource&.to_json
          }
        end

        def to_json(*_args)
          JSON.generate(to_storage_h)
        end

        def self.storage_format?(hash)
          hash.key?('model') || hash.key?(:model) ||
            hash.key?('model_class') || hash.key?(:model_class)
        end

        def self.from_storage_h(hash)
          h = hash.transform_keys(&:to_s)
          new(
            url: h['url'],
            cached_at: h['cached_at'],
            metadata: h['metadata'] ? CacheMetadata.from_json(h['metadata']) : nil,
            hal_resource: rebuild_model(h['model_class'], h['model'])
          )
        end

        def self.rebuild_model(class_name, model_json)
          return nil unless class_name && model_json

          Object.const_get(class_name).from_json(model_json)
        rescue NameError
          nil
        end

        def self.create(url, response, hal_resource)
          new(
            url: url,
            cached_at: Time.now.to_s,
            metadata: CacheMetadata.from_response(response),
            hal_resource: hal_resource
          )
        end

        def valid?(default_ttl)
          return false unless cached_at

          cached_time = cached_at.is_a?(String) ? Time.parse(cached_at) : cached_at
          age = Time.now - cached_time
          ttl = metadata&.max_age || default_ttl

          age < ttl
        end

        def expired?(default_ttl)
          !valid?(default_ttl)
        end

        def revalidatable?
          return false unless metadata

          !!(metadata.etag || metadata.last_modified)
        end

        def conditional_headers
          metadata&.conditional_headers || {}
        end

        def cacheable?
          metadata&.cacheable? != false
        end

        def refresh_metadata(response)
          self.cached_at = Time.now.to_s
          self.metadata = CacheMetadata.from_response(response)
        end

        def age
          return 0 unless cached_at

          cached_time = cached_at.is_a?(String) ? Time.parse(cached_at) : cached_at
          Time.now - cached_time
        end

        def serve_stale?(max_stale = nil)
          return false unless max_stale
          return false if valid?(Float::INFINITY)

          cached_time = cached_at.is_a?(String) ? Time.parse(cached_at) : cached_at
          current_age = Time.now - cached_time
          ttl = metadata&.max_age || 0

          staleness = current_age - ttl
          current_age > ttl && staleness < max_stale
        end
      end
    end
  end
end
