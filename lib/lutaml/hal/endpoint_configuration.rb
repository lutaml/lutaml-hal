# frozen_string_literal: true

module Lutaml
  module Hal
    # Configuration object for endpoint registration with EndpointParameter support
    class EndpointConfiguration
      attr_reader :endpoint_path, :parameters

      def initialize
        @endpoint_path = nil
        @parameters = []
      end

      # Set the endpoint path
      def path(path_string)
        @endpoint_path = path_string
      end

      # Add a parameter to this endpoint
      def add_parameter(parameter)
        @parameters << parameter
      end

      # Add multiple parameters
      def parameters=(param_list)
        @parameters = param_list || []
      end

      # DSL method to add path parameter
      def path_parameter(name, **options)
        add_parameter(EndpointParameter.path(name, **options))
      end

      # DSL method to add query parameter
      def query_parameter(name, **options)
        add_parameter(EndpointParameter.query(name, **options))
      end

      # DSL method to add header parameter
      def header_parameter(name, **options)
        add_parameter(EndpointParameter.header(name, **options))
      end

      # DSL method to add cookie parameter
      def cookie_parameter(name, **options)
        add_parameter(EndpointParameter.cookie(name, **options))
      end
    end
  end
end
