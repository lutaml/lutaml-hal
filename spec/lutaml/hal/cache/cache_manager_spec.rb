# frozen_string_literal: true

require 'rspec'
require_relative '../../../../lib/lutaml/hal/cache/cache_manager'
require_relative '../../../../lib/lutaml/hal/cache/cache_configuration'
require_relative '../../../../lib/lutaml/hal/cache/cache_entry'
require_relative '../../../../lib/lutaml/hal/cache/cache_metadata'

RSpec.describe Lutaml::Hal::Cache::CacheManager do
  let(:hal_resource) { double('HAL Resource') }
  let(:response) do
    {
      'etag' => '"abc123"',
      'last-modified' => 'Wed, 21 Oct 2015 07:28:00 GMT',
      'cache-control' => 'max-age=3600, public'
    }
  end

  describe '#initialize' do
    context 'with valid configuration' do
      let(:config) { { adapter: :memory, ttl: 1800 } }

      it 'creates cache manager with configuration' do
        manager = described_class.new(config)

        expect(manager.configuration).to be_a(Lutaml::Hal::Cache::CacheConfiguration)
        expect(manager.configuration.effective_ttl).to eq(1800)
      end
    end

    context 'with nil configuration' do
      it 'creates cache manager with default configuration' do
        manager = described_class.new(nil)

        expect(manager.configuration).to be_a(Lutaml::Hal::Cache::CacheConfiguration)
        expect(manager.configuration.effective_ttl).to eq(3600)
      end
    end

    context 'with invalid configuration' do
      it 'raises validation error' do
        expect { described_class.new({ adapter_type: 'invalid' }) }.to raise_error(ArgumentError, /Invalid cache configuration/)
      end
    end
  end

  describe '#available?' do
    context 'when cache store is available' do
      let(:manager) { described_class.new({ adapter: :memory }) }

      before do
        # Mock the cache store availability
        stub_const('CACHE_STORE_AVAILABLE', true)
        allow(manager).to receive(:cache_store).and_return(double('cache_store'))
      end

      it 'returns true' do
        expect(manager.available?).to be true
      end
    end

    context 'when cache store is not available' do
      let(:manager) { described_class.new({ adapter: :memory }) }

      before do
        allow(manager).to receive(:cache_store).and_return(nil)
      end

      it 'returns false' do
        expect(manager.available?).to be false
      end
    end
  end

  describe '#get' do
    let(:manager) { described_class.new({ adapter: :memory }) }
    let(:cache_store) { double('cache_store') }
    let(:url) { 'http://example.com/api/resource' }

    before do
      allow(manager).to receive(:cache_store).and_return(cache_store)
    end

    context 'with HTTP-aware cache' do
      before do
        allow(manager).to receive(:http_aware_cache?).and_return(true)
      end

      it 'delegates to get_from_http_cache' do
        expect(manager).to receive(:get_from_http_cache).with(url, 'hal_resource:http://example.com/api/resource')
        manager.get(url)
      end
    end

    context 'with basic cache' do
      before do
        allow(manager).to receive(:http_aware_cache?).and_return(false)
      end

      it 'delegates to get_from_basic_cache' do
        expect(manager).to receive(:get_from_basic_cache).with('hal_resource:http://example.com/api/resource')
        manager.get(url)
      end
    end

    context 'without cache store' do
      before do
        allow(manager).to receive(:cache_store).and_return(nil)
      end

      it 'returns nil' do
        expect(manager.get(url)).to be_nil
      end
    end
  end

  describe '#set' do
    let(:manager) { described_class.new({ adapter: :memory }) }
    let(:cache_store) { double('cache_store') }
    let(:url) { 'http://example.com/api/resource' }

    before do
      allow(manager).to receive(:cache_store).and_return(cache_store)
    end

    context 'with cacheable response' do
      it 'creates and stores cache entry' do
        expect(Lutaml::Hal::Cache::CacheEntry).to receive(:create)
          .with(url, response, hal_resource)
          .and_return(double('entry', cacheable?: true))

        expect(manager).to receive(:set_in_basic_cache)
        allow(manager).to receive(:http_aware_cache?).and_return(false)

        result = manager.set(url, response, hal_resource)
        expect(result).not_to be_nil
      end
    end

    context 'with non-cacheable response' do
      let(:non_cacheable_response) { { 'cache-control' => 'no-cache' } }

      it 'does not store entry' do
        expect(Lutaml::Hal::Cache::CacheEntry).to receive(:create)
          .with(url, non_cacheable_response, hal_resource)
          .and_return(double('entry', cacheable?: false))

        expect(manager).not_to receive(:set_in_basic_cache)
        expect(manager).not_to receive(:set_in_http_cache)

        result = manager.set(url, non_cacheable_response, hal_resource)
        expect(result).to be_nil
      end
    end

    context 'without cache store' do
      before do
        allow(manager).to receive(:cache_store).and_return(nil)
      end

      it 'returns nil without storing' do
        expect(manager.set(url, response, hal_resource)).to be_nil
      end
    end
  end

  describe '#conditional_request_headers' do
    let(:manager) { described_class.new({ adapter: :memory }) }
    let(:url) { 'http://example.com/api/resource' }

    context 'with revalidatable cache entry' do
      let(:cache_entry) do
        double('entry',
               revalidatable?: true,
               conditional_headers: { 'If-None-Match' => '"abc123"' })
      end

      it 'returns conditional headers' do
        allow(manager).to receive(:get).with(url).and_return(cache_entry)

        headers = manager.conditional_request_headers(url)
        expect(headers).to eq({ 'If-None-Match' => '"abc123"' })
      end
    end

    context 'with non-revalidatable cache entry' do
      let(:cache_entry) { double('entry', revalidatable?: false) }

      it 'returns empty hash' do
        allow(manager).to receive(:get).with(url).and_return(cache_entry)

        headers = manager.conditional_request_headers(url)
        expect(headers).to eq({})
      end
    end

    context 'without cache entry' do
      it 'returns empty hash' do
        allow(manager).to receive(:get).with(url).and_return(nil)

        headers = manager.conditional_request_headers(url)
        expect(headers).to eq({})
      end
    end
  end

  describe '#refresh_entry' do
    let(:manager) { described_class.new({ adapter: :memory }) }
    let(:url) { 'http://example.com/api/resource' }
    let(:cache_entry) { double('entry') }
    let(:new_response) { { 'etag' => '"new456"' } }

    context 'with existing cache entry' do
      it 'refreshes metadata and stores updated entry' do
        allow(manager).to receive(:get).with(url).and_return(cache_entry)
        expect(cache_entry).to receive(:refresh_metadata).with(new_response)
        expect(manager).to receive(:set_refreshed_entry).with(url, cache_entry)

        manager.refresh_entry(url, new_response)
      end
    end

    context 'without existing cache entry' do
      it 'does nothing' do
        allow(manager).to receive(:get).with(url).and_return(nil)
        expect(manager).not_to receive(:set_refreshed_entry)

        manager.refresh_entry(url, new_response)
      end
    end
  end

  describe '#invalidate' do
    let(:manager) { described_class.new({ adapter: :memory }) }
    let(:cache_store) { double('cache_store') }
    let(:url) { 'http://example.com/api/resource' }

    before do
      allow(manager).to receive(:cache_store).and_return(cache_store)
    end

    it 'deletes cache entry' do
      expect(cache_store).to receive(:delete).with('hal_resource:http://example.com/api/resource')
      manager.invalidate(url)
    end

    context 'without cache store' do
      before do
        allow(manager).to receive(:cache_store).and_return(nil)
      end

      it 'does nothing' do
        expect { manager.invalidate(url) }.not_to raise_error
      end
    end
  end

  describe '#clear' do
    let(:manager) { described_class.new({ adapter: :memory }) }
    let(:cache_store) { double('cache_store') }

    before do
      allow(manager).to receive(:cache_store).and_return(cache_store)
    end

    it 'clears all cache entries' do
      expect(cache_store).to receive(:clear)
      manager.clear
    end

    context 'without cache store' do
      before do
        allow(manager).to receive(:cache_store).and_return(nil)
      end

      it 'does nothing' do
        expect { manager.clear }.not_to raise_error
      end
    end
  end

  describe '#stats' do
    let(:manager) { described_class.new({ adapter: :memory }) }
    let(:cache_store) { double('cache_store') }

    before do
      allow(manager).to receive(:cache_store).and_return(cache_store)
    end

    context 'with cache_info method' do
      it 'returns cache info' do
        stats_data = { hits: 10, misses: 5 }
        allow(cache_store).to receive(:respond_to?).with(:cache_info).and_return(true)
        allow(cache_store).to receive(:cache_info).and_return(stats_data)

        expect(manager.stats).to eq(stats_data)
      end
    end

    context 'with stats method' do
      it 'returns stats' do
        stats_data = { requests: 15, hit_rate: 0.67 }
        allow(cache_store).to receive(:respond_to?).with(:cache_info).and_return(false)
        allow(cache_store).to receive(:respond_to?).with(:stats).and_return(true)
        allow(cache_store).to receive(:stats).and_return(stats_data)

        expect(manager.stats).to eq(stats_data)
      end
    end

    context 'without stats methods' do
      it 'returns empty hash' do
        allow(cache_store).to receive(:respond_to?).and_return(false)

        expect(manager.stats).to eq({})
      end
    end

    context 'without cache store' do
      before do
        allow(manager).to receive(:cache_store).and_return(nil)
      end

      it 'returns empty hash' do
        expect(manager.stats).to eq({})
      end
    end
  end

  describe '#info' do
    let(:manager) { described_class.new({ adapter: :memory }) }
    let(:cache_store) { double('cache_store', class: double(name: 'MockCacheStore')) }

    before do
      allow(manager).to receive(:cache_store).and_return(cache_store)
    end

    it 'returns cache information' do
      allow(cache_store).to receive(:respond_to?).with(:size).and_return(true)
      allow(cache_store).to receive(:size).and_return(42)
      allow(manager).to receive(:stats).and_return({ hits: 10 })

      info = manager.info

      expect(info[:adapter_type]).to eq('MockCacheStore')
      expect(info[:configuration]).to eq(manager.configuration)
      expect(info[:current_size]).to eq(42)
      expect(info[:stats]).to eq({ hits: 10 })
    end

    context 'without cache store' do
      before do
        allow(manager).to receive(:cache_store).and_return(nil)
      end

      it 'returns nil' do
        expect(manager.info).to be_nil
      end
    end
  end

  describe '#http_aware_cache?' do
    let(:manager) { described_class.new({ adapter: :memory }) }

    context 'when configuration is http_aware and cache store supports fetch' do
      let(:cache_store) { double('cache_store') }

      before do
        allow(manager).to receive(:cache_store).and_return(cache_store)
        allow(manager.configuration).to receive(:http_aware?).and_return(true)
        allow(cache_store).to receive(:respond_to?).with(:fetch).and_return(true)
      end

      it 'returns true' do
        expect(manager.http_aware_cache?).to be true
      end
    end

    context 'when configuration is not http_aware' do
      before do
        allow(manager.configuration).to receive(:http_aware?).and_return(false)
      end

      it 'returns false' do
        expect(manager.http_aware_cache?).to be false
      end
    end

    context 'when cache store does not support fetch' do
      let(:cache_store) { double('cache_store') }

      before do
        allow(manager).to receive(:cache_store).and_return(cache_store)
        allow(manager.configuration).to receive(:http_aware?).and_return(true)
        allow(cache_store).to receive(:respond_to?).with(:fetch).and_return(false)
      end

      it 'returns false' do
        expect(manager.http_aware_cache?).to be false
      end
    end
  end

  describe 'private methods' do
    let(:manager) { described_class.new({ adapter: :memory }) }

    describe '#cache_key' do
      it 'generates cache key with prefix' do
        key = manager.send(:cache_key, 'http://example.com/api/resource')
        expect(key).to eq('hal_resource:http://example.com/api/resource')
      end
    end

    describe '#get_from_basic_cache' do
      let(:cache_store) { double('cache_store') }
      let(:key) { 'hal_resource:http://example.com/api/resource' }

      before do
        allow(manager).to receive(:cache_store).and_return(cache_store)
      end

      context 'with valid CacheEntry' do
        let(:cache_entry) do
          Lutaml::Hal::Cache::CacheEntry.new(url: 'http://example.com', hal_resource: hal_resource).tap do |entry|
            allow(entry).to receive(:valid?).and_return(true)
          end
        end

        it 'returns cache entry if valid' do
          allow(cache_store).to receive(:get).with(key).and_return(cache_entry)
          allow(manager.configuration).to receive(:effective_ttl).and_return(3600)

          result = manager.send(:get_from_basic_cache, key)
          expect(result).to eq(cache_entry)
        end
      end

      context 'with expired CacheEntry' do
        let(:cache_entry) { double('CacheEntry', valid?: false) }

        it 'returns nil if expired' do
          allow(cache_store).to receive(:get).with(key).and_return(cache_entry)
          allow(manager.configuration).to receive(:effective_ttl).and_return(3600)

          result = manager.send(:get_from_basic_cache, key)
          expect(result).to be_nil
        end
      end

      context 'with legacy hash format' do
        let(:legacy_data) do
          {
            realized_model: hal_resource,
            cached_at: Time.now,
            etag: '"abc123"',
            url: 'http://example.com/api/resource'
          }
        end

        it 'converts legacy format to CacheEntry' do
          allow(cache_store).to receive(:get).with(key).and_return(legacy_data)
          expect(manager).to receive(:convert_legacy_cache_data).with(legacy_data)

          manager.send(:get_from_basic_cache, key)
        end
      end

      context 'with invalid data' do
        it 'returns nil for invalid data' do
          allow(cache_store).to receive(:get).with(key).and_return('invalid')

          result = manager.send(:get_from_basic_cache, key)
          expect(result).to be_nil
        end
      end

      context 'with no cached data' do
        it 'returns nil' do
          allow(cache_store).to receive(:get).with(key).and_return(nil)

          result = manager.send(:get_from_basic_cache, key)
          expect(result).to be_nil
        end
      end
    end
  end
end
