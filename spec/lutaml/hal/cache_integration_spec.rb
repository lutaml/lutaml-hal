# frozen_string_literal: true

require 'rspec'
require 'json'

require 'tmpdir'

require_relative '../../../lib/lutaml/hal/model_register'
require_relative '../../../lib/lutaml/hal/resource'
require_relative '../../../lib/lutaml/hal/cache/cache_manager'
require_relative '../../../lib/lutaml/hal/cache/cache_configuration'
require_relative '../../../lib/lutaml/hal/cache/cache_entry'
require_relative '../../../lib/lutaml/hal/cache/cache_metadata'

# A *named* resource class, required because persisted cache entries record the
# model's class name in order to rebuild it on retrieval.
class CachePersistenceResource < Lutaml::Hal::Resource
  attribute :id, :string
  attribute :name, :string
  key_value do
    map 'id', to: :id
    map 'name', to: :name
  end
end

RSpec.describe 'Cache Integration' do
  let(:mock_client) { double('client', api_url: 'https://api.example.com') }
  let(:cache_config) { { adapter: :memory, ttl: 3600 } }
  let(:register) { Lutaml::Hal::ModelRegister.new(name: 'test', client: mock_client, cache: cache_config) }

  # Mock HAL resource class
  let(:mock_resource_class) do
    Class.new(Lutaml::Hal::Resource) do
      attribute :id, :string
      attribute :name, :string
      attribute :description, :string

      def self.from_json(json)
        data = JSON.parse(json)
        new(
          id: data['id'],
          name: data['name'],
          description: data['description']
        )
      end

      def to_h
        { 'id' => id, 'name' => name, 'description' => description }
      end
    end
  end

  let(:response_data) do
    {
      'id' => '123',
      'name' => 'Test Resource',
      'description' => 'A test resource',
      'etag' => '"abc123"',
      'last-modified' => 'Wed, 21 Oct 2015 07:28:00 GMT',
      'cache-control' => 'max-age=3600, public'
    }
  end

  let(:mock_response) do
    double('response',
           to_json: response_data.to_json,
           to_h: response_data,
           headers: {
             'etag' => '"abc123"',
             'last-modified' => 'Wed, 21 Oct 2015 07:28:00 GMT',
             'cache-control' => 'max-age=3600, public'
           }).tap do |response|
      # Allow array access for _embedded and other keys
      allow(response).to receive(:[]).with('_embedded').and_return(nil)
      allow(response).to receive(:[]) do |key|
        response_data[key]
      end
    end
  end

  before do
    # Need to require endpoint_parameter for the parameter definition
    require_relative '../../../lib/lutaml/hal/endpoint_parameter'

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

        # Verify cache entry was created
        cache_stats = register.cache_stats
        expect(cache_stats).to be_a(Hash)
      end
    end

    context 'on subsequent request with valid cache' do
      it 'returns cached result without HTTP request' do
        # First request - populates cache
        expect(mock_client).to receive(:get).with(url).and_return(mock_response)
        register.fetch(:test_resource, id: '123')

        # Second request - should use cache
        expect(mock_client).not_to receive(:get)
        result = register.fetch(:test_resource, id: '123')

        expect(result).to be_a(mock_resource_class)
        expect(result.id).to eq('123')
      end
    end

    context 'with conditional request support' do
      let(:conditional_response) do
        double('response',
               status: 304,
               headers: { 'etag' => '"abc123"' })
      end

      it 'makes conditional request and uses cached data on 304' do
        # First request - populates cache
        expect(mock_client).to receive(:get).with(url).and_return(mock_response)
        register.fetch(:test_resource, id: '123')

        # Mock client to support conditional requests
        allow(mock_client).to receive(:get_with_headers) do |_url, headers|
          expect(headers['If-None-Match']).to eq('"abc123"')
          conditional_response
        end

        # Second request - should make conditional request
        result = register.fetch(:test_resource, id: '123')

        expect(result).to be_a(mock_resource_class)
        expect(result.id).to eq('123')
      end
    end

    context 'with non-cacheable response' do
      let(:non_cacheable_response) do
        response_data_no_cache = response_data.merge('cache-control' => 'no-cache')
        double('response',
               to_json: response_data_no_cache.to_json,
               to_h: response_data_no_cache,
               headers: { 'cache-control' => 'no-cache' }).tap do |response|
          # Allow array access for _embedded and other keys
          allow(response).to receive(:[]).with('_embedded').and_return(nil)
          allow(response).to receive(:[]) do |key|
            response_data_no_cache[key]
          end
        end
      end

      it 'does not cache the response' do
        expect(mock_client).to receive(:get).with(url).and_return(non_cacheable_response).twice

        # First request
        result1 = register.fetch(:test_resource, id: '123')
        expect(result1.id).to eq('123')

        # Second request - should make another HTTP request
        result2 = register.fetch(:test_resource, id: '123')
        expect(result2.id).to eq('123')
      end
    end
  end

  describe 'resolve_and_cast with caching' do
    let(:href) { 'https://api.example.com/resources/456' }
    let(:link) { double('link') }

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
        # First resolution - populates cache
        expect(mock_client).to receive(:get_by_url).with(href).and_return(mock_response)
        register.resolve_and_cast(link, href)

        # Second resolution - should use cache
        expect(mock_client).not_to receive(:get_by_url)
        result = register.resolve_and_cast(link, href)

        expect(result).to be_a(mock_resource_class)
        expect(result.id).to eq('123')
      end
    end

    context 'with conditional request support' do
      let(:conditional_response) do
        double('response',
               status: 304,
               headers: { 'etag' => '"abc123"' })
      end

      it 'makes conditional request and uses cached data on 304' do
        # First resolution - populates cache
        expect(mock_client).to receive(:get_by_url).with(href).and_return(mock_response)
        register.resolve_and_cast(link, href)

        # Mock client to support conditional requests
        allow(mock_client).to receive(:get_by_url_with_headers) do |_url, headers|
          expect(headers['If-None-Match']).to eq('"abc123"')
          conditional_response
        end

        # Second resolution - should make conditional request
        result = register.resolve_and_cast(link, href)

        expect(result).to be_a(mock_resource_class)
        expect(result.id).to eq('123')
      end
    end
  end

  describe 'cross-path cache sharing' do
    # A resource fetched by its (relative) endpoint path and the same resource
    # realized from its absolute link href must resolve to the same cache entry,
    # so a document linked from many places is only fetched once.
    it 'serves a realized link from the entry populated by fetch' do
      expect(mock_client).to receive(:get).with('/resources/123').and_return(mock_response).once
      register.fetch(:test_resource, id: '123')

      expect(mock_client).not_to receive(:get_by_url)
      result = register.resolve_and_cast(double('link'), 'https://api.example.com/resources/123')

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

        # Next request should make HTTP call again
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

    context 'with HTTP-aware cache configuration' do
      let(:cache_config) do
        {
          adapter: :memory,
          http_aware: true,
          respect_http_headers: true,
          enable_conditional_requests: true
        }
      end

      it 'uses HTTP-aware cache features' do
        expect(mock_client).to receive(:get).and_return(mock_response)

        result = register.fetch(:test_resource, id: '123')
        expect(result.id).to eq('123')

        info = register.cache_info
        expect(info[:configuration].http_aware).to be true
        expect(info[:configuration].respect_http_headers).to be true
        expect(info[:configuration].enable_conditional_requests).to be true
      end
    end

    context 'with disabled HTTP awareness' do
      let(:cache_config) { { adapter: :memory, http_aware: false } }

      it 'uses basic cache without HTTP features' do
        expect(mock_client).to receive(:get).and_return(mock_response)

        result = register.fetch(:test_resource, id: '123')
        expect(result.id).to eq('123')

        info = register.cache_info
        expect(info[:configuration].http_aware).to be false
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

        # Both requests should make HTTP calls
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

      # First request
      register.fetch(:test_resource, id: '123')

      # Second request with same parameters should use cache
      result = register.fetch(:test_resource, id: '123')
      expect(result.id).to eq('123')
    end

    it 'generates different cache keys for different URLs' do
      expect(mock_client).to receive(:get).with('/resources/123').and_return(mock_response)
      expect(mock_client).to receive(:get).with('/resources/456').and_return(mock_response)

      # Different IDs should result in different cache keys
      register.fetch(:test_resource, id: '123')
      register.fetch(:test_resource, id: '456')
    end
  end

  describe 'legacy cache data migration' do
    let(:legacy_cache_data) do
      {
        realized_model: mock_resource_class.new(id: '123', name: 'Legacy Resource'),
        cached_at: Time.now - 1800,
        etag: '"legacy123"',
        url: 'https://api.example.com/resources/123'
      }
    end

    it 'handles legacy cache format gracefully' do
      # Simulate legacy cache data in the cache store
      cache_manager = register.instance_variable_get(:@cache_manager)
      cache_store = cache_manager.send(:cache_store)

      if cache_store
        # fetch keys the cache by the canonical absolute URL
        cache_store.set('hal_resource:https://api.example.com/resources/123', legacy_cache_data)

        # Should convert legacy data and return the resource
        result = register.fetch(:test_resource, id: '123')
        expect(result.name).to eq('Legacy Resource')
      end
    end
  end

  describe 'filesystem persistence' do
    let(:cache_dir) { Dir.mktmpdir('hal-cache-spec') }
    let(:cache_config) do
      { adapter: { type: :filesystem, options: { path: cache_dir, integrity_checks: false } }, ttl: 3600 }
    end

    let(:persist_response) do
      double('response',
             to_json: { 'id' => '123', 'name' => 'Persisted' }.to_json,
             to_h: { 'id' => '123', 'name' => 'Persisted' },
             headers: {}).tap do |response|
        allow(response).to receive(:[]).and_return(nil)
      end
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
      # First register fetches and writes the entry to disk
      expect(mock_client).to receive(:get).with('/resources/123').and_return(persist_response).once
      first = build_register.fetch(:persist_resource, id: '123')
      expect(first.name).to eq('Persisted')

      # A brand-new register (and cache manager) over the same directory must
      # serve the rebuilt model without any HTTP request
      expect(mock_client).not_to receive(:get)
      second = build_register.fetch(:persist_resource, id: '123')

      expect(second).to be_a(CachePersistenceResource)
      expect(second.id).to eq('123')
      expect(second.name).to eq('Persisted')
    end
  end
end
