# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Lutaml::Hal::Cache::CacheEntry do
  let(:url) { 'http://example.com/api/resource' }
  let(:hal_resource) { Struct.new(:id, :name).new('res-1', 'Resource') }
  let(:response) do
    {
      'etag' => '"abc123"',
      'last-modified' => 'Wed, 21 Oct 2015 07:28:00 GMT',
      'cache-control' => 'max-age=3600, public'
    }
  end

  describe '.create' do
    it 'creates a cache entry with current timestamp' do
      freeze_time = Time.parse('2015-10-21 07:28:00 UTC')
      allow(Time).to receive(:now).and_return(freeze_time)

      entry = described_class.create(url, response, hal_resource)

      expect(entry.url).to eq(url)
      expect(entry.cached_at).to eq(freeze_time.to_s)
      expect(entry.metadata).to be_a(Lutaml::Hal::Cache::CacheMetadata)
      expect(entry.hal_resource).to eq(hal_resource)
    end
  end

  describe '#valid?' do
    let(:cached_at) { Time.parse('2015-10-21 07:28:00 GMT') }
    let(:entry) do
      described_class.new(
        url: 'http://example.com/api/resource',
        cached_at: cached_at,
        hal_resource: hal_resource,
        metadata: Lutaml::Hal::Cache::CacheMetadata.new(cache_control: 'max-age=3600')
      )
    end

    context 'when entry is fresh' do
      it 'returns true if within TTL' do
        current_time = cached_at + 1800
        allow(Time).to receive(:now).and_return(current_time)

        expect(entry.valid?(7200)).to be true
      end

      it 'uses metadata max-age over default TTL' do
        current_time = cached_at + 1800
        allow(Time).to receive(:now).and_return(current_time)

        expect(entry.valid?(300)).to be true
      end
    end

    context 'when entry is expired' do
      it 'returns false if beyond TTL' do
        current_time = cached_at + 7200
        allow(Time).to receive(:now).and_return(current_time)

        expect(entry.valid?(3600)).to be false
      end

      it 'returns false if beyond metadata max-age' do
        current_time = cached_at + 4000
        allow(Time).to receive(:now).and_return(current_time)

        expect(entry.valid?(7200)).to be false
      end
    end

    context 'without cached_at' do
      let(:entry) do
        described_class.new(
          url: 'http://example.com/api/resource',
          hal_resource: hal_resource
        )
      end

      it 'returns false' do
        expect(entry.valid?(3600)).to be false
      end
    end
  end

  describe '#expired?' do
    let(:entry) do
      described_class.new(
        url: 'http://example.com/api/resource',
        cached_at: Time.parse('2015-10-21 07:28:00 GMT'),
        hal_resource: hal_resource
      )
    end

    it 'returns opposite of valid?' do
      allow(entry).to receive(:valid?).with(3600).and_return(true)
      expect(entry.expired?(3600)).to be false

      allow(entry).to receive(:valid?).with(3600).and_return(false)
      expect(entry.expired?(3600)).to be true
    end
  end

  describe '#revalidatable?' do
    context 'with etag' do
      let(:entry) do
        described_class.new(
          metadata: Lutaml::Hal::Cache::CacheMetadata.new(etag: '"abc123"')
        )
      end

      it 'returns true' do
        expect(entry.revalidatable?).to be true
      end
    end

    context 'with last-modified' do
      let(:entry) do
        described_class.new(
          metadata: Lutaml::Hal::Cache::CacheMetadata.new(last_modified: 'Wed, 21 Oct 2015 07:28:00 GMT')
        )
      end

      it 'returns true' do
        expect(entry.revalidatable?).to be true
      end
    end

    context 'without validation headers' do
      let(:entry) do
        described_class.new(
          metadata: Lutaml::Hal::Cache::CacheMetadata.new
        )
      end

      it 'returns false' do
        expect(entry.revalidatable?).to be false
      end
    end

    context 'without metadata' do
      let(:entry) { described_class.new }

      it 'returns false' do
        expect(entry.revalidatable?).to be false
      end
    end
  end

  describe '#conditional_headers' do
    let(:metadata) do
      Lutaml::Hal::Cache::CacheMetadata.new(
        etag: '"abc123"',
        last_modified: 'Wed, 21 Oct 2015 07:28:00 GMT'
      )
    end
    let(:entry) { described_class.new(metadata: metadata) }

    it 'delegates to metadata' do
      expect(metadata).to receive(:conditional_headers).and_return({ 'If-None-Match' => '"abc123"' })

      headers = entry.conditional_headers
      expect(headers).to eq({ 'If-None-Match' => '"abc123"' })
    end

    context 'without metadata' do
      let(:entry) { described_class.new }

      it 'returns empty hash' do
        expect(entry.conditional_headers).to eq({})
      end
    end
  end

  describe '#cacheable?' do
    context 'with cacheable metadata' do
      let(:metadata) { Lutaml::Hal::Cache::CacheMetadata.new(cache_control: 'max-age=3600') }
      let(:entry) { described_class.new(metadata: metadata) }

      it 'returns true' do
        expect(entry.cacheable?).to be true
      end
    end

    context 'with non-cacheable metadata' do
      let(:metadata) { Lutaml::Hal::Cache::CacheMetadata.new(cache_control: 'no-cache') }
      let(:entry) { described_class.new(metadata: metadata) }

      it 'returns false' do
        expect(entry.cacheable?).to be false
      end
    end

    context 'without metadata' do
      let(:entry) { described_class.new }

      it 'returns true (default)' do
        expect(entry.cacheable?).to be true
      end
    end
  end

  describe '#refresh_metadata' do
    let(:entry) do
      described_class.new(
        cached_at: Time.parse('2015-10-21 07:28:00 GMT'),
        metadata: Lutaml::Hal::Cache::CacheMetadata.new(etag: '"old123"')
      )
    end

    let(:new_response) do
      {
        'etag' => '"new456"',
        'cache-control' => 'max-age=7200'
      }
    end

    it 'updates cached_at and metadata' do
      new_time = Time.parse('2015-10-21 08:28:00 GMT')
      allow(Time).to receive(:now).and_return(new_time)

      entry.refresh_metadata(new_response)

      expect(entry.cached_at).to eq(new_time.to_s)
      expect(entry.metadata.etag).to eq('"new456"')
      expect(entry.metadata.cache_control).to eq('max-age=7200')
    end
  end

  describe '#age' do
    let(:cached_at) { Time.parse('2015-10-21 07:28:00 GMT') }
    let(:entry) do
      described_class.new(
        cached_at: cached_at,
        hal_resource: hal_resource
      )
    end

    it 'returns age in seconds' do
      current_time = cached_at + 1800
      allow(Time).to receive(:now).and_return(current_time)

      expect(entry.age).to eq(1800)
    end

    context 'without cached_at' do
      let(:entry) { described_class.new(hal_resource: hal_resource) }

      it 'returns 0' do
        expect(entry.age).to eq(0)
      end
    end
  end

  describe '#serve_stale?' do
    let(:cached_at) { Time.parse('2015-10-21 07:28:00 GMT') }
    let(:entry) do
      described_class.new(
        cached_at: cached_at,
        hal_resource: hal_resource,
        metadata: Lutaml::Hal::Cache::CacheMetadata.new(cache_control: 'max-age=3600')
      )
    end

    context 'when entry is still fresh' do
      it 'returns false' do
        current_time = cached_at + 1800
        allow(Time).to receive(:now).and_return(current_time)

        expect(entry.serve_stale?(7200)).to be false
      end
    end

    context 'when entry is stale but within max_stale' do
      it 'returns true' do
        current_time = cached_at + 5400
        allow(Time).to receive(:now).and_return(current_time)

        expect(entry.serve_stale?(7200)).to be true
      end
    end

    context 'when entry is beyond max_stale' do
      it 'returns false' do
        current_time = cached_at + 10_800
        allow(Time).to receive(:now).and_return(current_time)

        expect(entry.serve_stale?(7200)).to be false
      end
    end

    context 'without max_stale' do
      it 'returns false' do
        current_time = cached_at + 5400
        allow(Time).to receive(:now).and_return(current_time)

        expect(entry.serve_stale?(nil)).to be false
      end
    end
  end
end
