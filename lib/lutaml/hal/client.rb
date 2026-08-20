# frozen_string_literal: true

require 'faraday'
require 'faraday/follow_redirects'
require 'json'
require 'rainbow'

module Lutaml
  module Hal
    class Client
      # Thread-variable (not Thread#[], which is fiber-local) holding this
      # thread's most recent [client, response] pair. One fixed key, one entry
      # per thread: nothing accumulates as clients come and go.
      LAST_RESPONSE_KEY = :lutaml_hal_last_response

      attr_reader :api_url, :connection, :rate_limiter

      def initialize(options = {})
        @api_url = options[:api_url] || raise(ArgumentError, 'api_url is required')
        @connection = options[:connection] || create_connection
        @params_default = options[:params_default] || {}
        @debug = options[:debug] || !ENV['DEBUG_API'].nil?
        @rate_limiter = options[:rate_limiter] || RateLimiter.new(options[:rate_limiting] || {})
        @api_url = strip_api_url(@api_url)
      end

      # The raw Faraday response from the most recent request issued by *this*
      # thread, or nil if this thread has issued none through this client.
      # Instance-wide state would be unsafe: a single Client is routinely shared
      # across threads, and one thread must never observe another's response.
      #
      # Scoped to the thread's single most recent request rather than kept
      # per-client, so a thread retains exactly one response no matter how many
      # clients it uses. A thread that then issues a request through a different
      # client reports nil here.
      #
      # Note that under SingleFlight coalescing, follower threads issue no
      # request of their own, so their last_response is unchanged by the
      # coalesced fetch.
      def last_response
        client, response = Thread.current.thread_variable_get(LAST_RESPONSE_KEY)
        response if client.equal?(self)
      end

      def strip_api_url(url)
        url.sub(%r{/\Z}, '')
      end

      def get_by_url(url, params = {})
        path = strip_api_url(url)
        get(path, params)
      end

      def get_by_url_with_headers(url, headers = {})
        path = strip_api_url(url)
        get_with_headers(path, headers)
      end

      def get(url, params = {})
        with_faraday_errors do
          @rate_limiter.with_rate_limiting do
            handle_response(record_response(@connection.get(url, params)), url)
          end
        end
      end

      def get_with_headers(url, headers = {})
        with_faraday_errors do
          @rate_limiter.with_rate_limiting do
            response = @connection.get(url) do |req|
              headers.each { |key, value| req.headers[key] = value }
            end
            handle_response(record_response(response), url)
          end
        end
      end

      private

      def with_faraday_errors
        yield
      rescue Faraday::ConnectionFailed => e
        raise ConnectionError, "Connection failed: #{e.message}"
      rescue Faraday::TimeoutError => e
        raise TimeoutError, "Request timed out: #{e.message}"
      rescue Faraday::ParsingError => e
        raise ParsingError, "Response parsing error: #{e.message}"
      rescue Faraday::Adapter::Test::Stubs::NotFound => e
        raise LinkResolutionError, "Resource not found: #{e.message}"
      end

      # Publish the response on #last_response and return it, so callers keep
      # working with their own local reference rather than re-reading shared
      # state that another thread may already have replaced.
      def record_response(response)
        Thread.current.thread_variable_set(LAST_RESPONSE_KEY, [self, response])
        response
      end

      def create_connection
        Faraday.new(url: @api_url) do |conn|
          conn.use Faraday::FollowRedirects::Middleware
          conn.request :json
          conn.response :json, content_type: /\bjson$/
          conn.adapter Faraday.default_adapter
        end
      end

      def handle_response(response, url)
        debug_api_log(response, url) if @debug

        case response.status
        when 200..299
          response.body
        when 400
          raise BadRequestError, response_message(response)
        when 401
          raise UnauthorizedError, response_message(response)
        when 403
          raise ForbiddenError.new(response_message(response), response: response_context(response))
        when 404
          raise NotFoundError, response_message(response)
        when 429
          raise TooManyRequestsError.new(response_message(response), response: response_context(response))
        when 500..599
          raise ServerError.new(response_message(response), response: response_context(response))
        else
          raise Error, response_message(response)
        end
      end

      # HTTP context attached to retryable errors so callers (and RateLimiter)
      # can read Retry-After without holding on to the Faraday response.
      def response_context(response)
        { status: response.status, headers: response.headers }
      end

      def debug_api_log(response, url)
        if defined?(Rainbow)
          puts Rainbow("\n===== Lutaml::Hal DEBUG: HAL API REQUEST =====").blue
        else
          puts "\n===== Lutaml::Hal DEBUG: HAL API REQUEST ====="
        end

        puts "URL: #{url}"
        puts "Status: #{response.status}"

        puts "\nHeaders:"
        headers_hash = response.headers.to_h
        puts JSON.pretty_generate(headers_hash)

        puts "\nResponse body:"
        if response.body.is_a?(Hash) || response.body.is_a?(Array)
          puts JSON.pretty_generate(response.body)
        else
          puts response.body.inspect
        end

        if defined?(Rainbow)
          puts Rainbow("===== END DEBUG OUTPUT =====\n").blue
        else
          puts "===== END DEBUG OUTPUT =====\n"
        end
      end

      def response_message(response)
        message = "Status: #{response.status}"
        message += ", Error: #{response.body['error']}" if response.body.is_a?(Hash) && response.body['error']
        message
      end
    end
  end
end
