# frozen_string_literal: true

require 'faraday'
require 'faraday/follow_redirects'
require 'json'
require 'rainbow'
require_relative 'errors'
require_relative 'rate_limiter'

module Lutaml
  module Hal
    # HAL Client for making HTTP requests to HAL APIs
    class Client
      attr_reader :last_response, :api_url, :connection, :rate_limiter

      def initialize(options = {})
        @api_url = options[:api_url] || raise(ArgumentError, 'api_url is required')
        @connection = options[:connection] || create_connection
        @params_default = options[:params_default] || {}
        @debug = options[:debug] || !ENV['DEBUG_API'].nil?
        @cache = options[:cache] || {}
        @cache_enabled = options[:cache_enabled] || false
        @rate_limiter = options[:rate_limiter] || RateLimiter.new(options[:rate_limiting] || {})

        @api_url = strip_api_url(@api_url)
      end

      # Strip any trailing slash from the API URL
      def strip_api_url(url)
        url.sub(%r{/\Z}, '')
      end

      # Get a resource by its full URL
      def get_by_url(url, params = {})
        # Strip API endpoint if it's included
        path = strip_api_url(url)
        get(path, params)
      end

      # Make a GET request to the API
      def get(url, params = {})
        cache_key = "#{url}:#{params.to_json}"

        return @cache[cache_key] if @cache_enabled && @cache.key?(cache_key)

        response = @rate_limiter.with_rate_limiting do
          @last_response = @connection.get(url, params)
          handle_response(@last_response, url)
        end

        @cache[cache_key] = response if @cache_enabled
        response
      rescue Faraday::ConnectionFailed => e
        raise Lutaml::Hal::ConnectionError, "Connection failed: #{e.message}"
      rescue Faraday::TimeoutError => e
        raise Lutaml::Hal::TimeoutError, "Request timed out: #{e.message}"
      rescue Faraday::ParsingError => e
        raise Lutaml::Hal::ParsingError, "Response parsing error: #{e.message}"
      rescue Faraday::Adapter::Test::Stubs::NotFound => e
        raise Lutaml::Hal::LinkResolutionError, "Resource not found: #{e.message}"
      end

      # Make a GET request with custom headers
      def get_with_headers(url, headers = {})
        cache_key = "#{url}:#{headers.to_json}"

        return @cache[cache_key] if @cache_enabled && @cache.key?(cache_key)

        response = @rate_limiter.with_rate_limiting do
          @last_response = @connection.get(url) do |req|
            headers.each { |key, value| req.headers[key] = value }
          end
          handle_response(@last_response, url)
        end

        @cache[cache_key] = response if @cache_enabled
        response
      rescue Faraday::ConnectionFailed => e
        raise Lutaml::Hal::ConnectionError, "Connection failed: #{e.message}"
      rescue Faraday::TimeoutError => e
        raise Lutaml::Hal::TimeoutError, "Request timed out: #{e.message}"
      rescue Faraday::ParsingError => e
        raise Lutaml::Hal::ParsingError, "Response parsing error: #{e.message}"
      rescue Faraday::Adapter::Test::Stubs::NotFound => e
        raise Lutaml::Hal::LinkResolutionError, "Resource not found: #{e.message}"
      end

      private

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
        when 404
          raise NotFoundError, response_message(response)
        when 429
          TooManyRequestsError.new(response_message(response)).tap do |error|
            error.define_singleton_method(:response) { { status: response.status, headers: response.headers } }
            raise error
          end
        when 500..599
          ServerError.new(response_message(response)).tap do |error|
            error.define_singleton_method(:response) { { status: response.status, headers: response.headers } }
            raise error
          end
        else
          raise Error, response_message(response)
        end
      end

      def debug_api_log(response, url)
        if defined?(Rainbow)
          puts Rainbow("\n===== Lutaml::Hal DEBUG: HAL API REQUEST =====").blue
        else
          puts "\n===== Lutaml::Hal DEBUG: HAL API REQUEST ====="
        end

        puts "URL: #{url}"
        puts "Status: #{response.status}"

        # Format headers as JSON
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
