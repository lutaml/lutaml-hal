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
      def add_endpoint(id:, type:, url:, model:, query_params: nil)
        @models ||= {}

        raise "Model with ID #{id} already registered" if @models[id]
        if @models.values.any? { |m| m[:url] == url && m[:type] == type && m[:query_params] == query_params }
          raise "Duplicate URL pattern #{url} for type #{type}"
        end

        @models[id] = {
          id: id,
          type: type,
          url: url,
          model: model,
          query_params: query_params
        }
      end

      # Resolve and cast data to the appropriate model based on URL
      def fetch(endpoint_id, **params)
        endpoint = @models[endpoint_id] || raise("Unknown endpoint: #{endpoint_id}")
        raise 'Client not configured' unless client

        url = interpolate_url(endpoint[:url], params)
        response = client.get(build_url_with_query_params(url, endpoint[:query_params], params))

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

      def build_url_with_query_params(base_url, query_params_template, params)
        return base_url unless query_params_template

        query_params = []
        query_params_template.each do |param_name, param_template|
          # If the template is like {page}, look for the param in the passed params
          if param_template.is_a?(String) && param_template.match?(/\{(.+)\}/)
            param_key = param_template.match(/\{(.+)\}/)[1]
            query_params << "#{param_name}=#{params[param_key.to_sym]}" if params[param_key.to_sym]
          end
        end

        query_params.any? ? "#{base_url}?#{query_params.join('&')}" : base_url
      end

      def find_matching_model_class(href)
        @models.values.find do |model_data|
          matches_url_with_params?(model_data, href)
        end&.[](:model)
      end

      def matches_url_with_params?(model_data, href)
        pattern = model_data[:url]
        query_params = model_data[:query_params]

        return false unless pattern && href

        # Parse the href to separate path and query parameters
        uri = URI.parse(href.start_with?('http') ? href : "#{client&.api_url}#{href}")
        href_path = uri.path
        href_query_params = parse_query_params(uri.query)

        # Extract path from pattern (remove query parameters if any)
        pattern_path = pattern.split('?').first

        # Check if the path matches
        path_matches = if href.start_with?('/') && client&.api_url
          path_pattern = extract_path(pattern_path)
          pattern_match?(path_pattern, href_path) ||
            pattern_match?(pattern_path, href_path)
        else
          pattern_match?(pattern_path, href_path)
        end

        return false unless path_matches

        # If no query parameters are defined in the pattern, any query params in href are acceptable
        return true unless query_params

        # Check if query parameters match
        query_params.all? do |param_name, param_pattern|
          href_value = href_query_params[param_name]
          next false unless href_value

          # If pattern is a template like {page}, it matches any value
          if param_pattern.is_a?(String) && param_pattern.match?(/\{.+\}/)
            true
          else
            href_value == param_pattern.to_s
          end
        end
      end

      def parse_query_params(query_string)
        return {} unless query_string

        query_string.split('&').each_with_object({}) do |param, hash|
          key, value = param.split('=', 2)
          hash[key] = value if key
        end
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
        # Convert * wildcards to regex pattern - use .+ instead of [^/]+ to match query parameters
        regex = Regexp.new("^#{pattern_with_wildcards.gsub('*', '.+')}$")

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
