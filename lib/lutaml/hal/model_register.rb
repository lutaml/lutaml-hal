# frozen_string_literal: true

require_relative 'errors'

module Lutaml
  module Hal
    # Register to map URL patterns to model classes
    class ModelRegister
      attr_accessor :models, :client, :register_name

      def initialize(name:, client: nil)
        @register_name = name
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

        realized_model = endpoint[:model].from_json(response.to_json)

        mark_model_links_with_register(realized_model)
        realized_model
      end

      def resolve_and_cast(link, href)
        raise 'Client not configured' unless client

        Hal.debug_log("resolve_and_cast: link #{link}, href #{href}")
        response = client.get_by_url(href)

        # TODO: Merge full Link content into the resource?
        response_with_link_details = response.to_h.merge({ 'href' => href })

        href_path = href.sub(client.api_url, '')

        model_class = find_matching_model_class(href_path)
        raise LinkResolutionError, "Unregistered URL pattern: #{href}" unless model_class

        Hal.debug_log("resolve_and_cast: resolved to model_class #{model_class}")
        Hal.debug_log("resolve_and_cast: response: #{response.inspect}")
        Hal.debug_log("resolve_and_cast: amended: #{response_with_link_details}")

        model = model_class.from_json(response_with_link_details.to_json)
        mark_model_links_with_register(model)
        model
      end

      # Recursively mark all models in the link with the register name
      # This is used to ensure that all links in the model are registered
      # with the same register name for consistent resolution
      def mark_model_links_with_register(inspecting_model)
        return unless inspecting_model.is_a?(Lutaml::Model::Serializable)

        inspecting_model.instance_variable_set("@#{Hal::REGISTER_ID_ATTR_NAME}", @register_name)

        # Recursively process model attributes to mark links with this register
        inspecting_model.class.attributes.each_pair do |key, config|
          attr_type = config.type
          next unless attr_type < Lutaml::Hal::Resource ||
                      attr_type < Lutaml::Hal::Link ||
                      attr_type < Lutaml::Hal::LinkSet

          value = inspecting_model.send(key)
          next if value.nil?

          # Handle both array and single values with the same logic
          values = value.is_a?(Array) ? value : [value]
          values.each { |item| mark_model_links_with_register(item) }
        end

        inspecting_model
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

        Hal.debug_log("pattern_match?: regex: #{regex.inspect}")
        Hal.debug_log("pattern_match?: href to match #{url}")
        Hal.debug_log("pattern_match?: pattern to match #{pattern_with_wildcards}")

        matches = regex.match?(url)
        Hal.debug_log("pattern_match?: matches = #{matches}")

        matches
      end
    end
  end
end
