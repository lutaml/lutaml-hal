# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Lutaml::Hal::Cache::CacheConfiguration do
  describe '.from_config' do
    context 'with nil config' do
      it 'returns default configuration' do
        config = described_class.from_config(nil)

        expect(config.effective_adapter_type).to eq('memory')
        expect(config.effective_ttl).to eq(3600)
        expect(config.effective_max_size).to eq(1000)
      end
    end

    context 'with symbol config' do
      it 'creates configuration with adapter type' do
        config = described_class.from_config(:sqlite)

        expect(config.adapter_type).to eq('sqlite')
        expect(config.effective_adapter_type).to eq('sqlite')
      end
    end

    context 'with string config' do
      it 'creates configuration with adapter type' do
        config = described_class.from_config('filesystem')

        expect(config.adapter_type).to eq('filesystem')
        expect(config.effective_adapter_type).to eq('filesystem')
      end
    end

    context 'with hash config' do
      it 'creates configuration from hash' do
        hash_config = {
          adapter: { type: :sqlite, path: '/tmp/cache.db' },
          ttl: 7200,
          max_size: 2000
        }

        config = described_class.from_config(hash_config)

        expect(config.adapter_type).to eq('sqlite')
        expect(config.ttl).to eq(7200)
        expect(config.max_size).to eq(2000)
      end

      it 'handles string keys' do
        string_config = {
          'adapter' => { 'type' => 'memory' },
          'ttl' => 1800,
          'max_size' => 500
        }

        config = described_class.from_config(string_config)

        expect(config.adapter_type).to eq('memory')
        expect(config.ttl).to eq(1800)
        expect(config.max_size).to eq(500)
      end
    end

    context 'with invalid config' do
      it 'raises ArgumentError' do
        expect { described_class.from_config(123) }.to raise_error(ArgumentError, /Invalid cache configuration/)
      end
    end
  end

  describe '#validate!' do
    context 'with valid configuration' do
      it 'does not raise error' do
        config = described_class.new(
          adapter_type: 'memory',
          ttl: 3600,
          max_size: 1000
        )

        expect { config.validate! }.not_to raise_error
      end
    end

    context 'with invalid adapter type' do
      it 'raises ArgumentError' do
        config = described_class.new(adapter_type: 'invalid')
        expect { config.validate! }.to raise_error(ArgumentError, /Invalid adapter type/)
      end
    end

    context 'with invalid TTL' do
      it 'raises ArgumentError' do
        config = described_class.new(ttl: -1)
        expect { config.validate! }.to raise_error(ArgumentError, /TTL must be a positive integer/)
      end
    end

    context 'with invalid max_size' do
      it 'raises ArgumentError' do
        config = described_class.new(max_size: 0)
        expect { config.validate! }.to raise_error(ArgumentError, /Max size must be a positive integer/)
      end
    end

    context 'with invalid adapter_config' do
      it 'rejects a non-hash adapter_config during initialization' do
        expect { described_class.new(adapter_config: 'invalid') }.to raise_error(StandardError)
      end
    end
  end

  describe '#effective_*' do
    context 'with configured values' do
      it 'returns configured values' do
        config = described_class.new(
          adapter_type: 'sqlite',
          ttl: 7200,
          max_size: 2000
        )

        expect(config.effective_adapter_type).to eq('sqlite')
        expect(config.effective_ttl).to eq(7200)
        expect(config.effective_max_size).to eq(2000)
      end
    end

    context 'with nil values' do
      it 'returns default values' do
        config = described_class.new

        expect(config.effective_adapter_type).to eq('memory')
        expect(config.effective_ttl).to eq(3600)
        expect(config.effective_max_size).to eq(1000)
      end
    end
  end

  describe '#to_cache_store_config' do
    it 'returns config hash suitable for CacheStore' do
      config = described_class.new(
        adapter_type: 'memory',
        ttl: 1800,
        max_size: 500
      )

      store_config = config.to_cache_store_config

      expect(store_config[:adapter]).to eq({ type: :memory })
      expect(store_config[:default_ttl]).to eq(1800)
      expect(store_config[:max_size]).to eq(500)
    end

    it 'passes adapter options via adapter_options key' do
      config = described_class.new(
        adapter_type: 'filesystem',
        adapter_config: { options: { directory: '/tmp/cache' } }
      )

      store_config = config.to_cache_store_config

      expect(store_config[:adapter]).to eq({ type: :filesystem })
      expect(store_config[:adapter_options]).to eq({ directory: '/tmp/cache' })
    end
  end
end
