# frozen_string_literal: true

require 'lutaml-hal'
require 'faraday'
require 'timeout'

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
      expect { Lutaml::Hal::ForbiddenError }.not_to raise_error
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
    # Exercise handle_response in isolation: with the default rate limiter the
    # 403/429/5xx examples would run the real retry loop and genuinely sleep.
    let(:client_with_test_adapter) do
      described_class.new(api_url: api_url, connection: connection,
                          rate_limiter: Lutaml::Hal::RateLimiter.new(enabled: false))
    end

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

    it 'raises ForbiddenError for 403 status' do
      stubs.get('/forbidden') { [403, {}, { error: 'Forbidden' }] }

      expect { client_with_test_adapter.get('/forbidden') }
        .to raise_error(Lutaml::Hal::ForbiddenError, 'Status: 403')
    end

    it 'includes the body error in the message when the body is JSON' do
      stubs.get('/forbidden') do
        [403, { 'Content-Type' => 'application/json' }, '{"error":"Forbidden"}']
      end

      expect { client_with_test_adapter.get('/forbidden') }
        .to raise_error(Lutaml::Hal::ForbiddenError, 'Status: 403, Error: Forbidden')
    end

    it 'maps status codes identically in #get_with_headers' do
      stubs.get('/forbidden') { [403, {}, { error: 'Forbidden' }] }

      expect { client_with_test_adapter.get_with_headers('/forbidden') }
        .to raise_error(Lutaml::Hal::ForbiddenError)
    end

    describe 'error response context' do
      # The status/header context callers need to honour Retry-After.
      {
        403 => Lutaml::Hal::ForbiddenError,
        429 => Lutaml::Hal::TooManyRequestsError,
        503 => Lutaml::Hal::ServerError
      }.each do |status, error_class|
        it "exposes #response on #{error_class} for #{status}" do
          stubs.get('/limited') { [status, { 'Retry-After' => '42' }, { error: 'nope' }] }

          expect { client_with_test_adapter.get('/limited') }
            .to raise_error(error_class) { |error|
              expect(error.response[:status]).to eq(status)
              expect(error.response[:headers]['Retry-After']).to eq('42')
            }
        end
      end

      it 'leaves #response nil on errors raised without HTTP context' do
        expect(Lutaml::Hal::TooManyRequestsError.new('boom').response).to be_nil
      end
    end
  end

  describe 'thread safety' do
    let(:json_headers) { { 'Content-Type' => 'application/json' } }
    let(:stubs) do
      Faraday::Adapter::Test::Stubs.new(strict_mode: false) do |stub|
        %w[a b c d].each do |name|
          stub.get("/#{name}") { [200, json_headers, { 'url' => name }] }
        end
      end
    end
    let(:connection) do
      Faraday.new do |builder|
        builder.request :json
        builder.response :json, content_type: /\bjson$/
        builder.adapter :test, stubs
      end
    end
    let(:shared_client) { described_class.new(api_url: api_url, connection: connection) }

    it 'keeps #last_response isolated per thread' do
      a_done = Queue.new
      b_done = Queue.new

      thread_a = Thread.new do
        shared_client.get('/a')
        a_done << :go       # let B issue its request now that A has one in hand
        b_done.pop          # ...and only read last_response after B has finished
        shared_client.last_response.body
      end

      thread_b = Thread.new do
        a_done.pop
        shared_client.get('/b')
        b_done << :go
        shared_client.last_response.body
      end

      Timeout.timeout(5) do
        expect([thread_a.value, thread_b.value]).to eq([{ 'url' => 'a' }, { 'url' => 'b' }])
      end
    end

    it 'reports nil #last_response on a thread that has issued no request' do
      shared_client.get('/a')

      expect(Thread.new { shared_client.last_response }.value).to be_nil
    end

    it 'scopes #last_response to the client that issued the request' do
      other = described_class.new(api_url: api_url, connection: connection)
      shared_client.get('/a')
      other.get('/b')

      expect([other.last_response.body, shared_client.last_response]).to eq([{ 'url' => 'b' }, nil])
    end

    # A #get that returned another URL's body would need the shared-state read
    # this fix removed; with a local there is no window left to probe. A
    # multi-threaded stress loop was tried here and deliberately dropped: it
    # passes against the pre-fix code too (the stubs never block, so the threads
    # don't interleave), so it asserted nothing while costing 200 requests.
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
