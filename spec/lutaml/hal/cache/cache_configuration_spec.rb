# frozen_string_literal: true

require 'rspec'
require_relative '../../../../lib/lutaml/hal/cache/cache_configuration'

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
      let(:hash_config) do
        {
          adapter: { type: :sqlite, path: '/tmp/cache.db' },
          ttl: 7200,
          max_size: 2000,
          http_aware: true,
          respect_http_headers: false,
          enable_conditional_requests: true,
          ignore_query_params: ['timestamp']
        }
      end

      it 'creates configuration from hash' do
        config = described_class.from_config(hash_config)

        expect(config.adapter_type).to eq('sqlite')
        expect(config.ttl).to eq(7200)
        expect(config.max_size).to eq(2000)
        expect(config.http_aware).to be true
        expect(config.respect_http_headers).to be false
        expect(config.enable_conditional_requests).to be true
        expect(config.ignore_query_params).to eq(['timestamp'])
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
      let(:config) do
        described_class.new(
          adapter_type: 'memory',
          ttl: 3600,
          max_size: 1000
        )
      end

      it 'does not raise error' do
        expect { config.validate! }.not_to raise_error
      end
    end

    context 'with invalid adapter type' do
      let(:config) { described_class.new(adapter_type: 'invalid') }

      it 'raises ArgumentError' do
        expect { config.validate! }.to raise_error(ArgumentError, /Invalid adapter type/)
      end
    end

    context 'with invalid TTL' do
      let(:config) { described_class.new(ttl: -1) }

      it 'raises ArgumentError' do
        expect { config.validate! }.to raise_error(ArgumentError, /TTL must be a positive integer/)
      end
    end

    context 'with invalid max_size' do
      let(:config) { described_class.new(max_size: 0) }

      it 'raises ArgumentError' do
        expect { config.validate! }.to raise_error(ArgumentError, /Max size must be a positive integer/)
      end
    end

    context 'with invalid adapter_config' do
      it 'rejects a non-hash adapter_config during initialization' do
        expect { described_class.new(adapter_config: 'invalid') }.to raise_error(StandardError)
      end
    end
  end

  describe '#http_aware?' do
    context 'when http_aware is true and HTTP cache is available' do
      let(:config) { described_class.new(http_aware: true) }

      before do
        allow(config).to receive(:http_cache_available?).and_return(true)
      end

      it 'returns true' do
        expect(config.http_aware?).to be true
      end
    end

    context 'when http_aware is false' do
      let(:config) { described_class.new(http_aware: false) }

      it 'returns false' do
        expect(config.http_aware?).to be false
      end
    end

    context 'when HTTP cache is not available' do
      let(:config) { described_class.new(http_aware: true) }

      before do
        allow(config).to receive(:http_cache_available?).and_return(false)
      end

      it 'returns false' do
        expect(config.http_aware?).to be false
      end
    end

    context 'when http_aware is nil (default)' do
      let(:config) { described_class.new }

      before do
        allow(config).to receive(:http_cache_available?).and_return(true)
      end

      it 'returns false (HTTP-aware caching is opt-in)' do
        expect(config.http_aware?).to be false
      end
    end
  end

  describe '#basic_cache?' do
    let(:config) { described_class.new }

    it 'returns opposite of http_aware?' do
      allow(config).to receive(:http_aware?).and_return(true)
      expect(config.basic_cache?).to be false

      allow(config).to receive(:http_aware?).and_return(false)
      expect(config.basic_cache?).to be true
    end
  end

  describe '#effective_*' do
    context 'with configured values' do
      let(:config) do
        described_class.new(
          adapter_type: 'sqlite',
          ttl: 7200,
          max_size: 2000
        )
      end

      it 'returns configured values' do
        expect(config.effective_adapter_type).to eq('sqlite')
        expect(config.effective_ttl).to eq(7200)
        expect(config.effective_max_size).to eq(2000)
      end
    end

    context 'with nil values' do
      let(:config) { described_class.new }

      it 'returns default values' do
        expect(config.effective_adapter_type).to eq('memory')
        expect(config.effective_ttl).to eq(3600)
        expect(config.effective_max_size).to eq(1000)
      end
    end
  end

  describe '#http_cache_config' do
    let(:config) do
      described_class.new(
        adapter_type: 'sqlite',
        ttl: 7200,
        max_size: 2000,
        respect_http_headers: false,
        enable_conditional_requests: true,
        ignore_query_params: ['timestamp'],
        adapter_config: { path: '/tmp/cache.db' }
      )
    end

    it 'returns HTTP cache configuration hash' do
      http_config = config.http_cache_config

      expect(http_config[:adapter_type]).to eq(:sqlite)
      expect(http_config[:default_ttl]).to eq(7200)
      expect(http_config[:max_entries]).to eq(2000)
      expect(http_config[:respect_http_headers]).to be false
      expect(http_config[:enable_conditional_requests]).to be true
      expect(http_config[:ignore_query_params]).to eq(['timestamp'])
      expect(http_config[:path]).to eq('/tmp/cache.db')
    end

    context 'with default values' do
      let(:config) { described_class.new }

      it 'uses defaults for boolean flags' do
        http_config = config.http_cache_config

        expect(http_config[:respect_http_headers]).to be true
        expect(http_config[:enable_conditional_requests]).to be true
        expect(http_config[:ignore_query_params]).to eq([])
      end
    end
  end

  describe '#basic_cache_config' do
    let(:config) do
      described_class.new(
        adapter_type: 'filesystem',
        ttl: 1800,
        max_size: 500,
        adapter_config: { directory: '/tmp/cache' }
      )
    end

    it 'returns basic cache configuration hash' do
      basic_config = config.basic_cache_config

      expect(basic_config[:adapter]).to eq({ directory: '/tmp/cache' })
      expect(basic_config[:default_ttl]).to eq(1800)
      expect(basic_config[:max_size]).to eq(500)
    end

    context 'without adapter_config' do
      let(:config) { described_class.new(adapter_type: 'memory') }

      it 'uses default adapter config' do
        basic_config = config.basic_cache_config

        expect(basic_config[:adapter]).to eq({ type: :memory })
      end
    end
  end

  describe 'private methods' do
    describe '.extract_adapter_type' do
      it 'extracts type from hash with symbol key' do
        adapter_info = { type: :sqlite }
        result = described_class.send(:extract_adapter_type, adapter_info)
        expect(result).to eq('sqlite')
      end

      it 'extracts type from hash with string key' do
        adapter_info = { 'type' => 'filesystem' }
        result = described_class.send(:extract_adapter_type, adapter_info)
        expect(result).to eq('filesystem')
      end

      it 'handles symbol directly' do
        result = described_class.send(:extract_adapter_type, :memory)
        expect(result).to eq('memory')
      end

      it 'handles string directly' do
        result = described_class.send(:extract_adapter_type, 'sqlite')
        expect(result).to eq('sqlite')
      end

      it 'returns nil for invalid input' do
        result = described_class.send(:extract_adapter_type, 123)
        expect(result).to be_nil
      end
    end
  end
end
