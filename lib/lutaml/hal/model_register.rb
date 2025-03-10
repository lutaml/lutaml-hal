# frozen_string_literal: true

require_relative 'errors'

module Lutaml
  module Hal
    # Register to map URL patterns to model classes
    class ModelRegister
      attr_accessor :models, :client

      def initialize(client: nil)
        # If `client` is not set, it can be set later
        @client = client
        @models = {}
      end

      # Register a model with its base URL pattern
      def add_endpoint(id:, type:, url:, model:)
        @models ||= {}

        raise "Model with ID #{id} already registered" if @models[id]
        if @models.values.any? { |m| m[:url] == url && m[:type] == type }
          raise "Duplicate URL pattern #{url} for type #{type}"
        end

        @models[id] = {
          id: id,
          type: type,
          url: url,
          model: model
        }
      end

      # Resolve and cast data to the appropriate model based on URL
      def fetch(endpoint_id, **params)
        endpoint = @models[endpoint_id] || raise("Unknown endpoint: #{endpoint_id}")
        raise 'Client not configured' unless client

        url = interpolate_url(endpoint[:url], params)
        response = client.get(url)

        endpoint[:model].from_json(response.to_json)
      end

      def resolve_and_cast(href)
        raise 'Client not configured' unless client

        debug_log("href #{href}")
        response = client.get_by_url(href)

        # TODO: Merge more content into the resource
        response_with_link_details = response.to_h.merge({ 'href' => href })

        href_path = href.sub(client.api_url, '')
        model_class = find_matching_model_class(href_path)
        raise LinkResolutionError, "Unregistered URL pattern: #{href}" unless model_class

        debug_log("model_class #{model_class}")
        debug_log("response: #{response.inspect}")
        debug_log("amended: #{response_with_link_details}")

        model_class.from_json(response_with_link_details.to_json)
      end

      private

      def interpolate_url(url_template, params)
        params.reduce(url_template) do |url, (key, value)|
          url.gsub("{#{key}}", value.to_s)
        end
      end

      def find_matching_model_class(href)
        @models.values.find do |model_data|
          matches_url?(model_data[:url], href)
        end&.[](:model)
      end

      def matches_url?(pattern, href)
        return false unless pattern && href

        if href.start_with?('/') && client&.api_url
          # Try both with and without the API endpoint prefix
          path_pattern = extract_path(pattern)
          return pattern_match?(path_pattern, href) ||
                 pattern_match?(pattern, "#{client.api_url}#{href}")
        end

        pattern_match?(pattern, href)
      end

      def extract_path(pattern)
        return pattern unless client&.api_url && pattern.start_with?(client.api_url)

        pattern.sub(client.api_url, '')
      end

      # Match URL pattern (supports * wildcards and {param} templates)
      def pattern_match?(pattern, url)
        return false unless pattern && url

        # Convert {param} to wildcards for matching
        pattern_with_wildcards = pattern.gsub(/\{[^}]+\}/, '*')
        # Convert * wildcards to regex pattern
        regex = Regexp.new("^#{pattern_with_wildcards.gsub('*', '[^/]+')}$")
        regex.match?(url)
      end

      def debug_log(message)
        puts "DEBUG: #{message}" if ENV['DEBUG_API']
      end
    end
  end
end
