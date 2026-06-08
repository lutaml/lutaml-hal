# frozen_string_literal: true

require 'spec_helper'

class CacheManagerTestResource < Lutaml::Hal::Resource
  attribute :id, :string

  key_value do
    map 'id', to: :id
  end
end

RSpec.describe Lutaml::Hal::Cache::CacheManager do
  let(:response) do
    {
      'etag' => '"abc123"',
      'last-modified' => 'Wed, 21 Oct 2015 07:28:00 GMT',
      'cache-control' => 'max-age=3600, public'
    }
  end

  let(:hal_resource) { CacheManagerTestResource.new(id: '123') }

  describe '#initialize' do
    context 'with valid configuration' do
      it 'creates cache manager with configuration' do
        manager = described_class.new({ adapter: :memory, ttl: 1800 })

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
        expect do
          described_class.new({ adapter_type: 'invalid' })
        end.to raise_error(ArgumentError, /Invalid cache configuration/)
      end
    end
  end

  describe '#available?' do
    it 'returns true when cache store is created' do
      manager = described_class.new({ adapter: :memory })
      expect(manager.available?).to be true
    end
  end

  describe '#get and #set' do
    let(:manager) { described_class.new({ adapter: :memory }) }
    let(:url) { 'http://example.com/api/resource' }

    it 'stores and retrieves a cache entry' do
      manager.set(url, response, hal_resource)

      entry = manager.get(url)
      expect(entry).to be_a(Lutaml::Hal::Cache::CacheEntry)
      expect(entry.hal_resource).to be_a(CacheManagerTestResource)
      expect(entry.hal_resource.id).to eq('123')
    end

    it 'returns nil for unknown URLs' do
      expect(manager.get('http://example.com/unknown')).to be_nil
    end

    context 'with non-cacheable response' do
      let(:non_cacheable_response) { { 'cache-control' => 'no-cache' } }

      it 'does not store entry' do
        result = manager.set(url, non_cacheable_response, hal_resource)
        expect(result).to be_nil
        expect(manager.get(url)).to be_nil
      end
    end
  end

  describe '#conditional_request_headers' do
    let(:manager) { described_class.new({ adapter: :memory }) }
    let(:url) { 'http://example.com/api/resource' }

    context 'with revalidatable cache entry' do
      it 'returns conditional headers' do
        manager.set(url, response, hal_resource)

        headers = manager.conditional_request_headers(url)
        expect(headers['If-None-Match']).to eq('"abc123"')
      end
    end

    context 'without cache entry' do
      it 'returns empty hash' do
        headers = manager.conditional_request_headers(url)
        expect(headers).to eq({})
      end
    end
  end

  describe '#refresh_entry' do
    let(:manager) { described_class.new({ adapter: :memory }) }
    let(:url) { 'http://example.com/api/resource' }
    let(:new_response) { { 'etag' => '"new456"' } }

    it 'refreshes metadata for existing entry' do
      manager.set(url, response, hal_resource)

      new_time = Time.parse('2015-10-21 08:28:00 GMT')
      allow(Time).to receive(:now).and_return(new_time)

      manager.refresh_entry(url, new_response)

      entry = manager.get(url)
      expect(entry.metadata.etag).to eq('"new456"')
    end

    it 'does nothing when no entry exists' do
      expect { manager.refresh_entry(url, new_response) }.not_to raise_error
    end
  end

  describe '#invalidate' do
    let(:manager) { described_class.new({ adapter: :memory }) }
    let(:url) { 'http://example.com/api/resource' }

    it 'removes cache entry' do
      manager.set(url, response, hal_resource)
      expect(manager.get(url)).not_to be_nil

      manager.invalidate(url)
      expect(manager.get(url)).to be_nil
    end
  end

  describe '#clear' do
    let(:manager) { described_class.new({ adapter: :memory }) }

    it 'clears all cache entries' do
      manager.set('http://example.com/a', response, hal_resource)
      manager.set('http://example.com/b', response, hal_resource)

      manager.clear

      expect(manager.get('http://example.com/a')).to be_nil
      expect(manager.get('http://example.com/b')).to be_nil
    end
  end

  describe '#stats' do
    let(:manager) { described_class.new({ adapter: :memory }) }

    it 'returns cache statistics hash' do
      stats = manager.stats
      expect(stats).to be_a(Hash)
      expect(stats).to have_key(:total_entries)
    end
  end

  describe '#info' do
    let(:manager) { described_class.new({ adapter: :memory }) }

    it 'returns cache information' do
      info = manager.info
      expect(info).to be_a(Hash)
      expect(info).to have_key(:adapter_type)
      expect(info).to have_key(:configuration)
      expect(info).to have_key(:current_size)
      expect(info).to have_key(:stats)
    end
  end

  describe 'URL canonicalization' do
    let(:client) { Struct.new(:api_url).new('https://api.example.com') }
    let(:manager) { described_class.new({ adapter: :memory }, client: client) }

    it 'canonicalizes relative URLs using client api_url' do
      manager.set('/resources/123', response, hal_resource)

      entry = manager.get('/resources/123')
      expect(entry).not_to be_nil
      expect(entry.hal_resource.id).to eq('123')

      entry_absolute = manager.get('https://api.example.com/resources/123')
      expect(entry_absolute).not_to be_nil
    end
  end
end
