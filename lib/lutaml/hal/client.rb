# frozen_string_literal: true

require 'faraday'
require 'faraday/follow_redirects'
require 'json'
require 'rainbow'
require_relative 'errors'

module Lutaml
  module Hal
    # HAL Client for making HTTP requests to HAL APIs
    class Client
      attr_reader :last_response, :api_endpoint, :connection

      def initialize(options = {})
        @api_endpoint = options[:api_endpoint] || raise(ArgumentError, 'api_endpoint is required')
        @connection = options[:connection] || create_connection
        @params_default = options[:params_default] || {}
        @debug = options[:debug] || !ENV['DEBUG_API'].nil?
        @cache = options[:cache] || {}
        @cache_enabled = options[:cache_enabled] || false
      end

      # Get a resource by its full URL
      def get_by_url(url, params = {})
        # Strip API endpoint if it's included
        path = url.sub(%r{^#{@api_endpoint}/}, '')
        get(path, params)
      end

      # Make a GET request to the API
      def get(url, params = {})
        cache_key = "#{url}:#{params.to_json}"

        return @cache[cache_key] if @cache_enabled && @cache.key?(cache_key)

        @last_response = @connection.get(url, params)

        response = handle_response(@last_response, url)

        @cache[cache_key] = response if @cache_enabled
        response
      rescue Faraday::ConnectionFailed => e
        raise ConnectionError, "Connection failed: #{e.message}"
      rescue Faraday::TimeoutError => e
        raise TimeoutError, "Request timed out: #{e.message}"
      rescue Faraday::ParsingError => e
        raise ParsingError, "Response parsing error: #{e.message}"
      rescue Faraday::Adapter::Test::Stubs::NotFound => e
        raise LinkResolutionError, "Resource not found: #{e.message}"
      end

      private

      def create_connection
        Faraday.new(url: @api_endpoint) do |conn|
          conn.use Faraday::FollowRedirects::Middleware
          conn.request :json
          conn.response :json, content_type: /\bjson$/
          conn.adapter Faraday.default_adapter
        end
      end

      def handle_response(response, url)
        debug_log(response, url) if @debug

        case response.status
        when 200..299
          response.body
        when 400
          raise BadRequestError, response_message(response)
        when 401
          raise UnauthorizedError, response_message(response)
        when 404
          raise NotFoundError, response_message(response)
        when 500..599
          raise ServerError, response_message(response)
        else
          raise Error, response_message(response)
        end
      end

      def debug_log(response, url)
        if defined?(Rainbow)
          puts Rainbow("\n===== DEBUG: HAL API REQUEST =====").blue
        else
          puts "\n===== DEBUG: HAL API REQUEST ====="
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
