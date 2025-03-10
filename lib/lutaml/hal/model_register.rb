# frozen_string_literal: true

require_relative 'errors'

module Lutaml
  module Hal
    # Register to map URL patterns to model classes
    class ModelRegister
      attr_accessor :models, :client

      # Register a model with its base URL pattern
      def register(model_class, url_pattern)
        @models ||= {}
        @models[url_pattern] = model_class
      end

      # Resolve and cast data to the appropriate model based on URL
      def resolve_and_cast(href)
        raise 'Client not configured' unless client

        debug_log("href #{href}")
        response = client.get_by_url(href)
        response_with_link_details = response.to_h.merge({ 'href' => href })

        model_class = find_matching_model_class(href)
        raise LinkResolutionError, "Unregistered URL pattern: #{href}" unless model_class

        debug_log("model_class #{model_class}")
        debug_log("response: #{response.inspect}")
        debug_log("amended: #{response_with_link_details}")

        model_class.from_json(response_with_link_details.to_json)
      end

      private

      def find_matching_model_class(href)
        @models.find do |pattern, _|
          debug_log("pattern #{pattern}")
          matches_url?(pattern, href)
        end&.last
      end

      def matches_url?(pattern, href)
        return false unless pattern && href

        if href.start_with?('/') && client&.api_endpoint
          # Try both with and without the API endpoint prefix
          path_pattern = extract_path(pattern)
          return pattern_match?(path_pattern, href) ||
                 pattern_match?(pattern, "#{client.api_endpoint}#{href}")
        end

        pattern_match?(pattern, href)
      end

      def extract_path(pattern)
        return pattern unless client&.api_endpoint && pattern.start_with?(client.api_endpoint)

        pattern.sub(client.api_endpoint, '')
      end

      # Match URL pattern (supports * wildcards)
      def pattern_match?(pattern, url)
        return false unless pattern && url

        regex = Regexp.new("^#{pattern.gsub('*', '.*')}$")
        regex.match?(url)
      end

      def debug_log(message)
        puts "DEBUG: #{message}" if ENV['DEBUG_API']
      end
    end
  end
end
