# frozen_string_literal: true

require 'cgi'
require_relative 'errors'
require_relative 'endpoint_configuration'

module Lutaml
  module Hal
    # Register to map URL patterns to model classes with EndpointParameter support
    class ModelRegister
      attr_accessor :models, :client, :register_name

      def initialize(name:, client: nil)
        @register_name = name
        # If `client` is not set, it can be set later
        @client = client
        @models = {}
      end

      # Register a model with its URL pattern and parameters
      def add_endpoint(id:, type:, url:, model:, parameters: [])
        @models ||= {}

        raise "Model with ID #{id} already registered" if @models[id]

        # Validate all parameters
        parameters.each(&:validate!)

        # Ensure path parameters in URL have corresponding parameter definitions
        validate_path_parameters(url, parameters)

        # Check for duplicate endpoints
        if @models.values.any? do |m|
          m[:url] == url && m[:type] == type && parameters_match?(m[:parameters], parameters)
        end
          raise "Duplicate URL pattern #{url} for type #{type}"
        end

        @models[id] = {
          id: id,
          type: type,
          url: url,
          model: model,
          parameters: parameters
        }
      end

      # Register an endpoint using block configuration syntax
      def register_endpoint(id, model, type: :index)
        config = EndpointConfiguration.new
        yield(config) if block_given?

        raise ArgumentError, 'Endpoint path must be configured' unless config.endpoint_path

        add_endpoint(
          id: id,
          type: type,
          url: config.endpoint_path,
          model: model,
          parameters: config.parameters || []
        )
      end

      # Resolve and cast data to the appropriate model based on URL
      def fetch(endpoint_id, **params)
        endpoint = @models[endpoint_id] || raise("Unknown endpoint: #{endpoint_id}")
        raise 'Client not configured' unless client

        # Process parameters through EndpointParameter objects
        processed_params = process_parameters(endpoint[:parameters], params)

        # Build URL with path parameters
        url = build_url_with_path_params(endpoint[:url], processed_params[:path])

        # Add query parameters
        final_url = build_url_with_query_params(url, processed_params[:query])

        # Make request with headers
        response = if processed_params[:headers].any?
                     client.get_with_headers(final_url, processed_params[:headers])
                   else
                     client.get(final_url)
                   end

        realized_model = endpoint[:model].from_json(response.to_json)

        # Store embedded data for later resolution
        realized_model.instance_variable_set(:@_embedded, response['_embedded']) if response['_embedded']

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
          values.each do |item|
            mark_model_links_with_register(item)

            # If this is a Link, set the parent resource for automatic embedded content detection
            item.parent_resource = inspecting_model if item.is_a?(Lutaml::Hal::Link)
          end
        end

        inspecting_model
      end

      private

      def process_parameters(parameter_definitions, provided_params)
        result = { path: {}, query: {}, headers: {}, cookies: {} }

        parameter_definitions.each do |param_def|
          param_name = param_def.name.to_sym
          provided_value = provided_params[param_name]

          # Check required parameters
          if param_def.required && provided_value.nil?
            raise ArgumentError, "Required parameter '#{param_def.name}' is missing"
          end

          # Use default value if not provided
          value = provided_value || param_def.default_value

          # Skip if still nil and not required
          next if value.nil?

          # Validate parameter value
          unless param_def.validate_value(value)
            raise ArgumentError, "Invalid value for parameter '#{param_def.name}': #{value}"
          end

          # Store in appropriate category
          case param_def.location
          when :path
            result[:path][param_def.name] = value
          when :query
            result[:query][param_def.name] = value
          when :header
            result[:headers][param_def.name] = value
          when :cookie
            result[:cookies][param_def.name] = value
          end
        end

        result
      end

      def validate_path_parameters(url, parameters)
        # Extract path parameter names from URL template
        url_params = url.scan(/\{([^}]+)\}/).flatten

        # Find path parameters in parameter definitions
        path_params = parameters.select(&:path_parameter?).map(&:name)

        # Check that all URL parameters have definitions
        missing_params = url_params - path_params
        unless missing_params.empty?
          raise ArgumentError, "URL contains undefined path parameters: #{missing_params.join(', ')}"
        end

        # Check that all path parameter definitions are used in URL
        unused_params = path_params - url_params
        return if unused_params.empty?

        raise ArgumentError, "Path parameters defined but not used in URL: #{unused_params.join(', ')}"
      end

      def parameters_match?(params1, params2)
        return true if params1.nil? && params2.nil?
        return false if params1.nil? || params2.nil?
        return false if params1.length != params2.length

        params1.zip(params2).all? do |p1, p2|
          p1.name == p2.name && p1.location == p2.location
        end
      end

      def build_url_with_path_params(url_template, path_params)
        path_params.reduce(url_template) do |url, (key, value)|
          url.gsub("{#{key}}", value.to_s)
        end
      end

      def build_url_with_query_params(base_url, query_params, params = nil)
        # Handle both 2-argument and 3-argument calls for backward compatibility
        if params.nil?
          # 2-argument call: query_params is the final query parameters
          final_query_params = query_params
        else
          # 3-argument call: query_params is template, params contains values
          final_query_params = {}
          query_params.each do |key, template_value|
            if template_value.is_a?(String) && template_value.match?(/\{(\w+)\}/)
              param_name = template_value.match(/\{(\w+)\}/)[1].to_sym
              final_query_params[key] = params[param_name] if params[param_name]
            else
              final_query_params[key] = template_value
            end
          end
        end

        return base_url if final_query_params.empty?

        query_string = final_query_params.map { |key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join('&')
        "#{base_url}?#{query_string}"
      end

      # Interpolate path parameters in a URL template
      def interpolate_url(url_template, params)
        params.reduce(url_template) do |url, (key, value)|
          url.gsub("{#{key}}", value.to_s)
        end
      end

      def find_matching_model_class(href)
        # Find all matching patterns and select the most specific one (longest pattern)
        matching_models = @models.values.select do |model_data|
          matches_url_with_params?(model_data, href)
        end

        return nil if matching_models.empty?

        # Sort by pattern length (descending) to get the most specific match first
        result = matching_models.max_by { |model_data| model_data[:url].length }

        result[:model]
      end

      def matches_url_with_params?(model_data, href)
        pattern = model_data[:url]
        parameters = model_data[:parameters]

        return false unless pattern && href

        uri = parse_href_uri(href)
        pattern_path = extract_pattern_path(pattern)

        path_match_result = path_matches?(pattern_path, uri.path)
        return false unless path_match_result

        # Check query parameters if any are defined
        query_params = parameters.select(&:query_parameter?)
        return true if query_params.empty?

        parsed_query = parse_query_params(uri.query)
        query_params_match?(query_params, parsed_query)
      end

      def parse_href_uri(href)
        full_href = href.start_with?('http') ? href : "#{client&.api_url}#{href}"
        URI.parse(full_href)
      end

      def extract_pattern_path(pattern)
        pattern.split('?').first
      end

      def path_matches?(pattern_path, href_path)
        pattern_match?(pattern_path, href_path)
      end

      def query_params_match?(expected_params, actual_params)
        # Query parameters should be optional unless marked as required
        expected_params.all? do |param_def|
          actual_value = actual_params[param_def.name]

          # Required parameters must be present
          if param_def.required
            return false if actual_value.nil?

            return param_def.validate_value(actual_value)
          end

          # Optional parameters are always considered matching if not present
          return true if actual_value.nil?

          # If present, they must be valid
          param_def.validate_value(actual_value)
        end
      end

      def parse_query_params(query_string)
        return {} unless query_string

        query_string.split('&').each_with_object({}) do |param, hash|
          key, value = param.split('=', 2)
          hash[key] = CGI.unescape(value) if key && value
        end
      end

      # Match URL pattern (supports {param} templates)
      def pattern_match?(pattern, url)
        return false unless pattern && url

        # Convert {param} to wildcards for matching
        pattern_with_wildcards = pattern.gsub(/\{[^}]+\}/, '*')
        # Convert * wildcards to regex pattern - use [^/]+ to match path segments, not across slashes
        # This ensures that {param} only matches a single path segment
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
