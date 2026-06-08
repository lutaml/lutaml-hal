# frozen_string_literal: true

require 'cgi'

module Lutaml
  module Hal
    class ModelRegister
      attr_accessor :models, :client, :register_name, :cache_manager

      def initialize(name:, client: nil, cache: nil)
        @register_name = name
        @client = client
        @models = {}
        @cache_manager = Cache::CacheManager.new(cache, client: @client) if cache
        @single_flight = SingleFlight.new
      end

      def add_endpoint(id:, type:, url:, model:, parameters: [])
        @models ||= {}

        raise "Model with ID #{id} already registered" if @models[id]

        parameters.each(&:validate!)

        validate_path_parameters(url, parameters)

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

      def fetch(endpoint_id, **params)
        endpoint = @models[endpoint_id] || raise("Unknown endpoint: #{endpoint_id}")
        raise 'Client not configured' unless client

        processed_params = process_parameters(endpoint[:parameters], params)

        url = build_url_with_path_params(endpoint[:url], processed_params[:path])
        final_url = build_url_with_query_params(url, processed_params[:query])

        cached = cached_endpoint_model(final_url)
        return cached if cached

        coalesce(final_url) do
          cached_endpoint_model(final_url) ||
            fetch_uncached(endpoint, final_url, processed_params[:headers])
        end
      end

      def resolve_and_cast(link, href)
        raise 'Client not configured' unless client

        cached = cached_resolved_model(href)
        return cached if cached

        debug_log("resolve_and_cast: link #{link}, href #{href}")

        coalesce(href) do
          cached_resolved_model(href) || resolve_and_cast_uncached(href)
        end
      end

      def mark_model_links_with_register(inspecting_model)
        return unless inspecting_model.is_a?(Lutaml::Model::Serializable)

        inspecting_model._global_register_id = @register_name

        inspecting_model.class.attributes.each_pair do |key, config|
          attr_type = config.type
          next unless attr_type < Lutaml::Hal::Resource ||
                      attr_type < Lutaml::Hal::Link ||
                      attr_type < Lutaml::Hal::LinkSet

          value = inspecting_model.public_send(key)
          next if value.nil?

          values = value.is_a?(Array) ? value : [value]
          values.each do |item|
            mark_model_links_with_register(item)

            item.parent_resource = inspecting_model if item.is_a?(Lutaml::Hal::Link)
          end
        end

        inspecting_model
      end

      def cache_stats
        @cache_manager&.stats || {}
      end

      def clear_cache
        @cache_manager&.clear
      end

      def cache_info
        @cache_manager&.info
      end

      def find_matching_model_class(href)
        matching_models = @models.values.select do |model_data|
          matches_url_with_params?(model_data, href)
        end

        return nil if matching_models.empty?

        result = matching_models.max_by { |model_data| model_data[:url].length }

        result[:model]
      end

      private

      def debug_log(message)
        Hal.debug_log(message)
      end

      def coalesce(key, &block)
        return block.call unless @cache_manager&.available?

        @single_flight.run(key, &block)
      end

      def cached_endpoint_model(url)
        return nil unless @cache_manager&.available?

        entry = @cache_manager.get(url)
        return nil unless entry

        debug_log("Cache hit for fetch: #{url}")
        model = entry.hal_resource
        mark_model_links_with_register(model)
        model
      end

      def fetch_uncached(endpoint, final_url, headers)
        request_headers = headers.dup
        if @cache_manager&.available?
          conditional_headers = @cache_manager.conditional_request_headers(final_url)
          request_headers.merge!(conditional_headers) if conditional_headers
        end

        response = if request_headers.any?
                     client.get_with_headers(final_url, request_headers)
                   else
                     client.get(final_url)
                   end

        realized_model = build_model_from_response(response, final_url, endpoint[:model])

        realized_model.embedded_data = response['_embedded'] if realized_model && response && response['_embedded']
        mark_model_links_with_register(realized_model)
        realized_model
      end

      def cached_resolved_model(href)
        return nil unless @cache_manager&.available?

        entry = @cache_manager.get(href)
        return nil unless entry

        debug_log("Cache hit for: #{href}")
        model = entry.hal_resource
        mark_model_links_with_register(model)
        model
      end

      def resolve_and_cast_uncached(href)
        conditional_headers = @cache_manager&.conditional_request_headers(href) || {}

        response = if conditional_headers.any?
                     client.get_by_url_with_headers(href, conditional_headers)
                   else
                     client.get_by_url(href)
                   end

        href_path = href.sub(client.api_url, '')

        model_class = find_matching_model_class(href_path)
        raise LinkResolutionError, "Unregistered URL pattern: #{href}" unless model_class

        debug_log("resolve_and_cast: resolved to model_class #{model_class}")

        response_with_link_details = response.to_h.merge({ 'href' => href })
        model = model_class.from_json(response_with_link_details.to_json)
        mark_model_links_with_register(model)
        @cache_manager&.set(href, response, model)
        model
      end

      def build_model_from_response(response, url, model_class)
        if response.is_a?(Hash) && response['status'] == 304
          @cache_manager&.refresh_entry(url, response)
          cached_entry = @cache_manager.get(url)
          return cached_entry&.hal_resource
        end

        realized_model = model_class.from_json(response.to_json)
        @cache_manager&.set(url, response, realized_model)
        realized_model
      end

      def process_parameters(parameter_definitions, provided_params)
        result = { path: {}, query: {}, headers: {}, cookies: {} }

        parameter_definitions.each do |param_def|
          param_name = param_def.name.to_sym
          provided_value = provided_params[param_name]

          if param_def.required && provided_value.nil?
            raise ArgumentError, "Required parameter '#{param_def.name}' is missing"
          end

          value = provided_value || param_def.default_value

          next if value.nil?

          unless param_def.validate_value(value)
            raise ArgumentError, "Invalid value for parameter '#{param_def.name}': #{value}"
          end

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
        url_params = url.scan(/\{([^}]+)\}/).flatten

        path_params = parameters.select(&:path_parameter?).map(&:name)

        missing_params = url_params - path_params
        unless missing_params.empty?
          raise ArgumentError, "URL contains undefined path parameters: #{missing_params.join(', ')}"
        end

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
        if params.nil?
          final_query_params = query_params
        else
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

      def interpolate_url(url_template, params)
        params.reduce(url_template) do |url, (key, value)|
          url.gsub("{#{key}}", value.to_s)
        end
      end

      def matches_url_with_params?(model_data, href)
        pattern = model_data[:url]
        parameters = model_data[:parameters]

        return false unless pattern && href

        uri = parse_href_uri(href)
        pattern_path = extract_pattern_path(pattern)

        path_match_result = path_matches?(pattern_path, uri.path)
        return false unless path_match_result

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
        expected_params.all? do |param_def|
          actual_value = actual_params[param_def.name]

          if param_def.required
            return false if actual_value.nil?

            return param_def.validate_value(actual_value)
          end

          return true if actual_value.nil?

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

      def pattern_match?(pattern, url)
        return false unless pattern && url

        pattern_with_wildcards = pattern.gsub(/\{[^}]+\}/, '*')
        regex = Regexp.new("^#{pattern_with_wildcards.gsub('*', '[^/]+')}$")

        debug_log("pattern_match?: regex: #{regex.inspect}")
        debug_log("pattern_match?: href to match #{url}")
        debug_log("pattern_match?: pattern to match #{pattern_with_wildcards}")

        matches = regex.match?(url)
        debug_log("pattern_match?: matches = #{matches}")

        matches
      end
    end
  end
end
