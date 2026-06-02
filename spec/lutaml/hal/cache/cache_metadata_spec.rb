# frozen_string_literal: true

require 'rspec'
require_relative '../../../../lib/lutaml/hal/cache/cache_metadata'

RSpec.describe Lutaml::Hal::Cache::CacheMetadata do
  describe '.from_response' do
    context 'with hash response' do
      let(:response) do
        {
          'etag' => '"abc123"',
          'last-modified' => 'Wed, 21 Oct 2015 07:28:00 GMT',
          'cache-control' => 'max-age=3600, public',
          'expires' => 'Thu, 22 Oct 2015 07:28:00 GMT',
          'content-type' => 'application/hal+json',
          'date' => 'Wed, 21 Oct 2015 07:28:00 GMT',
          'vary' => 'Accept-Encoding'
        }
      end

      it 'extracts metadata from hash response' do
        metadata = described_class.from_response(response)

        expect(metadata.etag).to eq('"abc123"')
        expect(metadata.last_modified).to eq('Wed, 21 Oct 2015 07:28:00 GMT')
        expect(metadata.cache_control).to eq('max-age=3600, public')
        expect(metadata.expires).to eq('Thu, 22 Oct 2015 07:28:00 GMT')
        expect(metadata.content_type).to eq('application/hal+json')
        expect(metadata.date).to eq('Wed, 21 Oct 2015 07:28:00 GMT')
        expect(metadata.vary).to eq('Accept-Encoding')
        expect(metadata.status_code).to eq(200)
      end
    end

    context 'with response object with headers method' do
      let(:response) do
        double('response', headers: {
                 'etag' => '"def456"',
                 'cache-control' => 'no-cache'
               })
      end

      it 'extracts metadata from response headers' do
        metadata = described_class.from_response(response)

        expect(metadata.etag).to eq('"def456"')
        expect(metadata.cache_control).to eq('no-cache')
        expect(metadata.status_code).to eq(200)
      end
    end

    context 'with response object with status method' do
      let(:response) do
        double('response', status: 304, headers: { 'etag' => '"ghi789"' })
      end

      it 'extracts status code from response' do
        metadata = described_class.from_response(response)

        expect(metadata.status_code).to eq(304)
        expect(metadata.etag).to eq('"ghi789"')
      end
    end

    context 'with empty response' do
      it 'handles empty response gracefully' do
        metadata = described_class.from_response({})

        expect(metadata.etag).to be_nil
        expect(metadata.status_code).to eq(200)
      end
    end
  end

  describe '#conditional_headers' do
    let(:metadata) do
      described_class.new(
        etag: '"abc123"',
        last_modified: 'Wed, 21 Oct 2015 07:28:00 GMT'
      )
    end

    it 'generates conditional request headers' do
      headers = metadata.conditional_headers

      expect(headers['If-None-Match']).to eq('"abc123"')
      expect(headers['If-Modified-Since']).to eq('Wed, 21 Oct 2015 07:28:00 GMT')
    end

    context 'with only etag' do
      let(:metadata) { described_class.new(etag: '"abc123"') }

      it 'generates only If-None-Match header' do
        headers = metadata.conditional_headers

        expect(headers['If-None-Match']).to eq('"abc123"')
        expect(headers['If-Modified-Since']).to be_nil
      end
    end

    context 'with only last-modified' do
      let(:metadata) { described_class.new(last_modified: 'Wed, 21 Oct 2015 07:28:00 GMT') }

      it 'generates only If-Modified-Since header' do
        headers = metadata.conditional_headers

        expect(headers['If-None-Match']).to be_nil
        expect(headers['If-Modified-Since']).to eq('Wed, 21 Oct 2015 07:28:00 GMT')
      end
    end

    context 'with no validation headers' do
      let(:metadata) { described_class.new }

      it 'returns empty hash' do
        headers = metadata.conditional_headers

        expect(headers).to eq({})
      end
    end
  end

  describe '#cacheable?' do
    context 'with cacheable response' do
      let(:metadata) { described_class.new(cache_control: 'max-age=3600, public') }

      it 'returns true' do
        expect(metadata.cacheable?).to be true
      end
    end

    context 'with no-cache directive' do
      let(:metadata) { described_class.new(cache_control: 'no-cache') }

      it 'returns false' do
        expect(metadata.cacheable?).to be false
      end
    end

    context 'with no-store directive' do
      let(:metadata) { described_class.new(cache_control: 'no-store') }

      it 'returns false' do
        expect(metadata.cacheable?).to be false
      end
    end

    context 'with private directive' do
      let(:metadata) { described_class.new(cache_control: 'private, max-age=3600') }

      it 'returns false' do
        expect(metadata.cacheable?).to be false
      end
    end

    context 'with no cache-control header' do
      let(:metadata) { described_class.new }

      it 'returns true' do
        expect(metadata.cacheable?).to be true
      end
    end
  end

  describe '#max_age' do
    context 'with max-age directive' do
      let(:metadata) { described_class.new(cache_control: 'max-age=3600, public') }

      it 'extracts max-age value' do
        expect(metadata.max_age).to eq(3600)
      end
    end

    context 'with multiple directives' do
      let(:metadata) { described_class.new(cache_control: 'public, max-age=7200, must-revalidate') }

      it 'extracts max-age value' do
        expect(metadata.max_age).to eq(7200)
      end
    end

    context 'without max-age directive' do
      let(:metadata) { described_class.new(cache_control: 'public, must-revalidate') }

      it 'returns nil' do
        expect(metadata.max_age).to be_nil
      end
    end

    context 'with no cache-control header' do
      let(:metadata) { described_class.new }

      it 'returns nil' do
        expect(metadata.max_age).to be_nil
      end
    end
  end
end
