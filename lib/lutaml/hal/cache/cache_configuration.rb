# frozen_string_literal: true

require 'lutaml/model'

module Lutaml
  module Hal
    module Cache
      # Represents cache configuration with validation and defaults
      class CacheConfiguration < Lutaml::Model::Serializable
        attribute :adapter_type, :string
        attribute :adapter_config, :hash
        attribute :ttl, :integer
        attribute :max_size, :integer
        attribute :http_aware, :boolean
        attribute :respect_http_headers, :boolean
        attribute :enable_conditional_requests, :boolean
        attribute :ignore_query_params, :string

        # Default configuration values
        DEFAULT_TTL = 3600
        DEFAULT_MAX_SIZE = 1000
        DEFAULT_ADAPTER_TYPE = 'memory'

        # Create configuration from hash or symbol
        def self.from_config(config)
          return new if config.nil?

          case config
          when Hash
            from_hash(config)
          when Symbol, String
            from_simple_config(config)
          else
            raise ArgumentError, "Invalid cache configuration: #{config.inspect}"
          end
        end

        # Validate the configuration
        def validate!
          validate_adapter_type!
          validate_ttl!
          validate_max_size!
          validate_adapter_config!
        end

        # Check if HTTP-aware caching should be used
        def http_aware?
          http_aware != false && http_cache_available?
        end

        # Check if basic caching should be used
        def basic_cache?
          !http_aware?
        end

        # Get the effective TTL (with fallback to default)
        def effective_ttl
          ttl || DEFAULT_TTL
        end

        # Get the effective max size (with fallback to default)
        def effective_max_size
          max_size || DEFAULT_MAX_SIZE
        end

        # Get the effective adapter type (with fallback to default)
        def effective_adapter_type
          adapter_type || DEFAULT_ADAPTER_TYPE
        end

        # Get HTTP cache configuration hash
        def http_cache_config
          {
            adapter_type: effective_adapter_type.to_sym,
            default_ttl: effective_ttl,
            max_entries: effective_max_size,
            respect_http_headers: respect_http_headers != false,
            enable_conditional_requests: enable_conditional_requests != false,
            ignore_query_params: parse_ignore_query_params
          }.merge(adapter_config || {})
        end

        # Get basic cache configuration hash
        def basic_cache_config
          {
            adapter: adapter_config || { type: effective_adapter_type.to_sym },
            default_ttl: effective_ttl,
            max_size: effective_max_size
          }
        end

        private

        def self.from_hash(config)
          adapter_info = config[:adapter] || config['adapter'] || {}

          # Handle direct adapter_type specification
          adapter_type = config[:adapter_type] || config['adapter_type'] || extract_adapter_type(adapter_info)

          new(
            adapter_type: adapter_type,
            adapter_config: adapter_info.is_a?(Hash) ? adapter_info : nil,
            ttl: config[:ttl] || config['ttl'],
            max_size: config[:max_size] || config['max_size'],
            http_aware: config.key?(:http_aware) ? config[:http_aware] : config['http_aware'],
            respect_http_headers: config.key?(:respect_http_headers) ? config[:respect_http_headers] : config['respect_http_headers'],
            enable_conditional_requests: config.key?(:enable_conditional_requests) ? config[:enable_conditional_requests] : config['enable_conditional_requests'],
            ignore_query_params: config[:ignore_query_params] || config['ignore_query_params']
          )
        end

        def self.from_simple_config(config)
          new(adapter_type: config.to_s)
        end

        def self.extract_adapter_type(adapter_info)
          case adapter_info
          when Hash
            type = adapter_info[:type] || adapter_info['type']
            type&.to_s
          when Symbol, String
            adapter_info.to_s
          else
            nil
          end
        end

        def validate_adapter_type!
          valid_types = %w[memory filesystem sqlite]
          return if valid_types.include?(effective_adapter_type)

          raise ArgumentError, "Invalid adapter type: #{effective_adapter_type}. Valid types: #{valid_types.join(', ')}"
        end

        def validate_ttl!
          return unless ttl
          return if ttl.is_a?(Integer) && ttl > 0

          raise ArgumentError, "TTL must be a positive integer, got: #{ttl.inspect}"
        end

        def validate_max_size!
          return unless max_size
          return if max_size.is_a?(Integer) && max_size > 0

          raise ArgumentError, "Max size must be a positive integer, got: #{max_size.inspect}"
        end

        def validate_adapter_config!
          return unless adapter_config
          return if adapter_config.is_a?(Hash)

          raise ArgumentError, "Adapter config must be a hash, got: #{adapter_config.class}"
        end

        # Override the setter to validate before assignment
        def adapter_config=(value)
          if value && !value.is_a?(Hash)
            raise ArgumentError, "Adapter config must be a hash, got: #{value.class}"
          end
          super(value)
        end

        def http_cache_available?
          defined?(::Lutaml::Store::HttpCache)
        end

        def parse_ignore_query_params
          return [] unless ignore_query_params

          case ignore_query_params
          when String
            ignore_query_params.split(',').map(&:strip)
          when Array
            ignore_query_params
          else
            []
          end
        end
      end
    end
  end
end
