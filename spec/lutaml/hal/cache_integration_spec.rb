# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

class CachePersistenceResource < Lutaml::Hal::Resource
  attribute :id, :string
  attribute :name, :string
  key_value do
    map 'id', to: :id
    map 'name', to: :name
  end
end

class CacheIntegrationResource < Lutaml::Hal::Resource
  attribute :id, :string
  attribute :name, :string
  attribute :description, :string

  key_value do
    map 'id', to: :id
    map 'name', to: :name
    map 'description', to: :description
  end
end

RSpec.describe 'Cache Integration' do
  let(:mock_client) do
    client = Object.new
    allow(client).to receive(:api_url).and_return('https://api.example.com')
    allow(client).to receive(:get_with_headers) { |url, _headers| client.get(url) }
    allow(client).to receive(:get_by_url_with_headers) { |url, _headers| client.get_by_url(url) }
    client
  end
  let(:cache_config) { { adapter: :memory, ttl: 3600 } }
  let(:register) { Lutaml::Hal::ModelRegister.new(name: 'test', client: mock_client, cache: cache_config) }

  let(:mock_resource_class) { CacheIntegrationResource }

  let(:mock_response) do
    {
      'id' => '123',
      'name' => 'Test Resource',
      'description' => 'A test resource',
      'etag' => '"abc123"',
      'last-modified' => 'Wed, 21 Oct 2015 07:28:00 GMT',
      'cache-control' => 'max-age=3600, public'
    }
  end

  before do
    register.add_endpoint(
      id: :test_resource,
      type: :show,
      url: '/resources/{id}',
      model: mock_resource_class,
      parameters: [
        Lutaml::Hal::EndpointParameter.new(name: 'id', in: :path, required: true)
      ]
    )
  end

  describe 'fetch with caching' do
    let(:url) { '/resources/123' }

    context 'on first request' do
      it 'makes HTTP request and caches the result' do
        expect(mock_client).to receive(:get).with(url).and_return(mock_response)

        result = register.fetch(:test_resource, id: '123')

        expect(result).to be_a(mock_resource_class)
        expect(result.id).to eq('123')
        expect(result.name).to eq('Test Resource')

        cache_stats = register.cache_stats
        expect(cache_stats).to be_a(Hash)
      end
    end

    context 'on subsequent request with valid cache' do
      it 'returns cached result without HTTP request' do
        expect(mock_client).to receive(:get).with(url).and_return(mock_response)
        register.fetch(:test_resource, id: '123')

        expect(mock_client).not_to receive(:get)
        result = register.fetch(:test_resource, id: '123')

        expect(result).to be_a(mock_resource_class)
        expect(result.id).to eq('123')
      end
    end

    context 'with non-cacheable response' do
      let(:non_cacheable_response) do
        {
          'id' => '123',
          'name' => 'Test Resource',
          'description' => 'A test resource',
          'cache-control' => 'no-cache'
        }
      end

      it 'does not cache the response' do
        expect(mock_client).to receive(:get).with(url).and_return(non_cacheable_response).twice

        result1 = register.fetch(:test_resource, id: '123')
        expect(result1.id).to eq('123')

        result2 = register.fetch(:test_resource, id: '123')
        expect(result2.id).to eq('123')
      end
    end
  end

  describe 'resolve_and_cast with caching' do
    let(:href) { 'https://api.example.com/resources/456' }
    let(:link) { Struct.new(:href).new(href) }

    context 'on first resolution' do
      it 'makes HTTP request and caches the result' do
        expect(mock_client).to receive(:get_by_url).with(href).and_return(mock_response)

        result = register.resolve_and_cast(link, href)

        expect(result).to be_a(mock_resource_class)
        expect(result.id).to eq('123')
      end
    end

    context 'on subsequent resolution with valid cache' do
      it 'returns cached result without HTTP request' do
        expect(mock_client).to receive(:get_by_url).with(href).and_return(mock_response)
        register.resolve_and_cast(link, href)

        expect(mock_client).not_to receive(:get_by_url)
        result = register.resolve_and_cast(link, href)

        expect(result).to be_a(mock_resource_class)
        expect(result.id).to eq('123')
      end
    end
  end

  describe 'cross-path cache sharing' do
    it 'serves a realized link from the entry populated by fetch' do
      expect(mock_client).to receive(:get).with('/resources/123').and_return(mock_response).once
      register.fetch(:test_resource, id: '123')

      expect(mock_client).not_to receive(:get_by_url)
      result = register.resolve_and_cast(Struct.new(:href).new(nil), 'https://api.example.com/resources/123')

      expect(result).to be_a(mock_resource_class)
      expect(result.id).to eq('123')
    end
  end

  describe 'cache management' do
    let(:url) { '/resources/123' }

    before do
      expect(mock_client).to receive(:get).with(url).and_return(mock_response)
      register.fetch(:test_resource, id: '123')
    end

    describe '#cache_stats' do
      it 'returns cache statistics' do
        stats = register.cache_stats
        expect(stats).to be_a(Hash)
      end
    end

    describe '#cache_info' do
      it 'returns cache information' do
        info = register.cache_info
        expect(info).to be_a(Hash)
        expect(info).to have_key(:configuration)
      end
    end

    describe '#clear_cache' do
      it 'clears all cached entries' do
        register.clear_cache

        expect(mock_client).to receive(:get).with(url).and_return(mock_response)
        register.fetch(:test_resource, id: '123')
      end
    end
  end

  describe 'cache configuration variations' do
    context 'with memory cache' do
      let(:cache_config) { { adapter: :memory, ttl: 1800, max_size: 100 } }

      it 'uses memory cache with specified configuration' do
        expect(mock_client).to receive(:get).and_return(mock_response)

        result = register.fetch(:test_resource, id: '123')
        expect(result.id).to eq('123')

        info = register.cache_info
        expect(info[:configuration].effective_ttl).to eq(1800)
        expect(info[:configuration].effective_max_size).to eq(100)
      end
    end
  end

  describe 'error handling' do
    context 'when cache store is unavailable' do
      let(:register_no_cache) { Lutaml::Hal::ModelRegister.new(name: 'test', client: mock_client) }

      before do
        register_no_cache.add_endpoint(
          id: :test_resource,
          type: :show,
          url: '/resources/{id}',
          model: mock_resource_class,
          parameters: [
            Lutaml::Hal::EndpointParameter.new(name: 'id', in: :path, required: true)
          ]
        )
      end

      it 'works without caching' do
        expect(mock_client).to receive(:get).and_return(mock_response).twice

        result1 = register_no_cache.fetch(:test_resource, id: '123')
        result2 = register_no_cache.fetch(:test_resource, id: '123')

        expect(result1.id).to eq('123')
        expect(result2.id).to eq('123')
      end
    end

    context 'with invalid cache configuration' do
      it 'raises configuration error' do
        expect do
          Lutaml::Hal::ModelRegister.new(
            name: 'test',
            client: mock_client,
            cache: { adapter_type: 'invalid' }
          )
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe 'cache key generation' do
    it 'generates consistent cache keys for same URLs' do
      url = '/resources/123'

      expect(mock_client).to receive(:get).with(url).and_return(mock_response).once

      register.fetch(:test_resource, id: '123')

      result = register.fetch(:test_resource, id: '123')
      expect(result.id).to eq('123')
    end

    it 'generates different cache keys for different URLs' do
      expect(mock_client).to receive(:get).with('/resources/123').and_return(mock_response)
      expect(mock_client).to receive(:get).with('/resources/456').and_return(mock_response)

      register.fetch(:test_resource, id: '123')
      register.fetch(:test_resource, id: '456')
    end
  end

  describe 'filesystem persistence' do
    let(:cache_dir) { Dir.mktmpdir('hal-cache-spec') }
    let(:cache_config) do
      { adapter: { type: :filesystem, options: { path: cache_dir, integrity_checks: false } }, ttl: 3600 }
    end

    let(:persist_response) do
      { 'id' => '123', 'name' => 'Persisted' }
    end

    def build_register
      Lutaml::Hal::ModelRegister.new(name: 'persist', client: mock_client, cache: cache_config).tap do |reg|
        reg.add_endpoint(
          id: :persist_resource,
          type: :show,
          url: '/resources/{id}',
          model: CachePersistenceResource,
          parameters: [Lutaml::Hal::EndpointParameter.new(name: 'id', in: :path, required: true)]
        )
      end
    end

    after { FileUtils.remove_entry(cache_dir) if File.directory?(cache_dir) }

    it 'persists a realized model to disk and rebuilds it in a fresh register' do
      expect(mock_client).to receive(:get).with('/resources/123').and_return(persist_response).once
      first = build_register.fetch(:persist_resource, id: '123')
      expect(first.name).to eq('Persisted')

      expect(mock_client).not_to receive(:get)
      second = build_register.fetch(:persist_resource, id: '123')

      expect(second).to be_a(CachePersistenceResource)
      expect(second.id).to eq('123')
      expect(second.name).to eq('Persisted')
    end
  end
end
