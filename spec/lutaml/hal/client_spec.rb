# frozen_string_literal: true

require 'lutaml-hal'
require 'faraday'

RSpec.describe Lutaml::Hal::Client do
  let(:api_url) { 'https://api.example.com' }
  let(:client) { described_class.new(api_url: api_url) }

  describe 'error class accessibility' do
    it 'can reference all error classes without NameError' do
      # This test ensures all error classes are properly namespaced
      # and prevents the "uninitialized constant" issue we faced
      expect { Lutaml::Hal::ConnectionError }.not_to raise_error
      expect { Lutaml::Hal::TimeoutError }.not_to raise_error
      expect { Lutaml::Hal::ParsingError }.not_to raise_error
      expect { Lutaml::Hal::LinkResolutionError }.not_to raise_error
      expect { Lutaml::Hal::NotFoundError }.not_to raise_error
      expect { Lutaml::Hal::UnauthorizedError }.not_to raise_error
      expect { Lutaml::Hal::BadRequestError }.not_to raise_error
      expect { Lutaml::Hal::ServerError }.not_to raise_error
      expect { Lutaml::Hal::TooManyRequestsError }.not_to raise_error
    end
  end

  describe 'Faraday exception handling' do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:connection) do
      Faraday.new do |builder|
        builder.request :json
        builder.response :json, content_type: /\bjson$/
        builder.adapter :test, stubs
      end
    end
    let(:client_with_mocked_connection) { described_class.new(api_url: api_url, connection: connection) }

    describe '#get' do
      it 'converts Faraday::ConnectionFailed to Lutaml::Hal::ConnectionError' do
        stubs.get('/test') { raise Faraday::ConnectionFailed, 'Connection failed' }

        expect do
          client_with_mocked_connection.get('/test')
        end.to raise_error(Lutaml::Hal::ConnectionError, 'Connection failed: Connection failed')
      end

      it 'converts Faraday::TimeoutError to Lutaml::Hal::TimeoutError' do
        stubs.get('/test') { raise Faraday::TimeoutError, 'Request timeout' }

        expect do
          client_with_mocked_connection.get('/test')
        end.to raise_error(Lutaml::Hal::TimeoutError, 'Request timed out: Request timeout')
      end

      it 'converts Faraday::ParsingError to Lutaml::Hal::ParsingError' do
        stubs.get('/test') { raise Faraday::ParsingError, 'Parsing failed' }

        expect do
          client_with_mocked_connection.get('/test')
        end.to raise_error(Lutaml::Hal::ParsingError, 'Response parsing error: Parsing failed')
      end

      it 'converts other StandardError to Lutaml::Hal::LinkResolutionError' do
        stubs.get('/test') { raise Faraday::Adapter::Test::Stubs::NotFound, 'Unknown error' }

        expect do
          client_with_mocked_connection.get('/test')
        end.to raise_error(Lutaml::Hal::LinkResolutionError, 'Resource not found: Unknown error')
      end
    end

    describe '#get_with_headers' do
      it 'converts Faraday::ConnectionFailed to Lutaml::Hal::ConnectionError' do
        stubs.get('/test') { raise Faraday::ConnectionFailed, 'Connection failed' }

        expect do
          client_with_mocked_connection.get_with_headers('/test')
        end.to raise_error(Lutaml::Hal::ConnectionError,
                           'Connection failed: Connection failed')
      end

      it 'converts Faraday::TimeoutError to Lutaml::Hal::TimeoutError' do
        stubs.get('/test') { raise Faraday::TimeoutError, 'Request timeout' }

        expect do
          client_with_mocked_connection.get_with_headers('/test')
        end.to raise_error(Lutaml::Hal::TimeoutError, 'Request timed out: Request timeout')
      end

      it 'converts Faraday::ParsingError to Lutaml::Hal::ParsingError' do
        stubs.get('/test') { raise Faraday::ParsingError, 'Parsing failed' }

        expect do
          client_with_mocked_connection.get_with_headers('/test')
        end.to raise_error(Lutaml::Hal::ParsingError, 'Response parsing error: Parsing failed')
      end

      it 'converts other StandardError to Lutaml::Hal::LinkResolutionError' do
        stubs.get('/test') { raise Faraday::Adapter::Test::Stubs::NotFound, 'Unknown error' }

        expect do
          client_with_mocked_connection.get_with_headers('/test')
        end.to raise_error(Lutaml::Hal::LinkResolutionError,
                           'Resource not found: Unknown error')
      end
    end
  end

  describe 'HTTP status code error handling' do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:connection) do
      Faraday.new do |builder|
        builder.request :json
        builder.response :json, content_type: /\bjson$/
        builder.adapter :test, stubs
      end
    end
    let(:client_with_test_adapter) { described_class.new(api_url: api_url, connection: connection) }

    it 'raises BadRequestError for 400 status' do
      stubs.get('/bad-request') { [400, {}, { error: 'Bad Request' }] }

      expect { client_with_test_adapter.get('/bad-request') }
        .to raise_error(Lutaml::Hal::BadRequestError)
    end

    it 'raises UnauthorizedError for 401 status' do
      stubs.get('/unauthorized') { [401, {}, { error: 'Unauthorized' }] }

      expect { client_with_test_adapter.get('/unauthorized') }
        .to raise_error(Lutaml::Hal::UnauthorizedError)
    end

    it 'raises NotFoundError for 404 status' do
      stubs.get('/not-found') { [404, {}, { error: 'Not Found' }] }

      expect { client_with_test_adapter.get('/not-found') }
        .to raise_error(Lutaml::Hal::NotFoundError)
    end

    it 'raises TooManyRequestsError for 429 status' do
      stubs.get('/rate-limited') { [429, {}, { error: 'Too Many Requests' }] }

      expect { client_with_test_adapter.get('/rate-limited') }
        .to raise_error(Lutaml::Hal::TooManyRequestsError)
    end

    it 'raises ServerError for 500 status' do
      stubs.get('/server-error') { [500, {}, { error: 'Internal Server Error' }] }

      expect { client_with_test_adapter.get('/server-error') }
        .to raise_error(Lutaml::Hal::ServerError)
    end
  end

  describe 'successful requests' do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:connection) do
      Faraday.new do |builder|
        builder.request :json
        builder.response :json, content_type: /\bjson$/
        builder.adapter :test, stubs
      end
    end
    let(:client_with_test_adapter) { described_class.new(api_url: api_url, connection: connection) }

    it 'returns response body for successful GET request' do
      response_data = { 'message' => 'success' }
      stubs.get('/success') { [200, { 'Content-Type' => 'application/json' }, response_data] }

      result = client_with_test_adapter.get('/success')
      expect(result).to eq(response_data)
    end

    it 'returns response body for successful GET request with headers' do
      response_data = { 'message' => 'success' }
      response_headers = { 'X-Custom-Header' => 'custom-value' }
      stubs.get('/success') { [200, response_headers, response_data] }

      result = client_with_test_adapter.get_with_headers('/success', { 'Authorization' => 'Bearer token' })
      expect(result).to eq(response_data)
    end
  end
end
