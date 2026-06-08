# frozen_string_literal: true

require 'lutaml/model'

module Lutaml
  module Hal
    module Cache
      class CacheConfiguration < Lutaml::Model::Serializable
        attribute :adapter_type, :string
        attribute :adapter_config, :hash
        attribute :ttl, :integer
        attribute :max_size, :integer

        DEFAULT_TTL = 3600
        DEFAULT_MAX_SIZE = 1000
        DEFAULT_ADAPTER_TYPE = 'memory'

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

        def validate!
          validate_adapter_type!
          validate_ttl!
          validate_max_size!
          validate_adapter_config!
        end

        def effective_ttl
          ttl || DEFAULT_TTL
        end

        def effective_max_size
          max_size || DEFAULT_MAX_SIZE
        end

        def effective_adapter_type
          adapter_type || DEFAULT_ADAPTER_TYPE
        end

        def to_cache_store_config
          base = {
            adapter: { type: effective_adapter_type.to_sym },
            default_ttl: effective_ttl,
            max_size: effective_max_size
          }
          options = adapter_config&.dig(:options) || adapter_config&.dig('options')
          base[:adapter_options] = options if options
          base
        end

        private

        def self.from_hash(config)
          adapter_info = config[:adapter] || config['adapter'] || {}
          adapter_type = config_value(config, :adapter_type) || extract_adapter_type(adapter_info)

          new(
            adapter_type: adapter_type,
            adapter_config: adapter_info.is_a?(Hash) ? adapter_info : nil,
            ttl: config_value(config, :ttl),
            max_size: config_value(config, :max_size)
          )
        end
        private_class_method :from_hash

        def self.from_simple_config(config)
          new(adapter_type: config.to_s)
        end
        private_class_method :from_simple_config

        def self.extract_adapter_type(adapter_info)
          case adapter_info
          when Hash
            type = adapter_info[:type] || adapter_info['type']
            type&.to_s
          when Symbol, String
            adapter_info.to_s
          end
        end
        private_class_method :extract_adapter_type

        def self.config_value(config, key)
          config[key] || config[key.to_s]
        end
        private_class_method :config_value

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
      end
    end
  end
end
