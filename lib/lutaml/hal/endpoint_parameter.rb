# frozen_string_literal: true

module Lutaml
  module Hal
    # OpenAPI-inspired parameter definition for HAL endpoints
    class EndpointParameter
      attr_reader :name, :location, :required, :schema, :description, :example

      def initialize(name:, in:, required: nil, schema: {}, description: nil, example: nil)
        @name = name.to_s
        @location = validate_location(binding.local_variable_get(:in))
        @required = determine_required(required, @location)
        @schema = Schema.new(schema)
        @description = description
        @example = example

        validate!
      end

      # Convenience constructors for different parameter types
      def self.path(name, **options)
        new(name: name, in: :path, **options)
      end

      def self.query(name, **options)
        new(name: name, in: :query, **options)
      end

      def self.header(name, **options)
        new(name: name, in: :header, **options)
      end

      def self.cookie(name, **options)
        new(name: name, in: :cookie, **options)
      end

      # Parameter type checks
      def path_parameter?
        @location == :path
      end

      def query_parameter?
        @location == :query
      end

      def header_parameter?
        @location == :header
      end

      def cookie_parameter?
        @location == :cookie
      end

      # Validate a parameter value against this parameter's schema
      def validate_value(value)
        @schema.validate(value)
      end

      # Get the default value for this parameter
      def default_value
        @schema.default
      end

      def validate!
        # Path parameters must be required
        raise ArgumentError, 'Path parameters must be required' if path_parameter? && !@required

        @schema.validate_definition!
      end

      private

      def validate_location(location)
        valid_locations = %i[path query header cookie]
        unless valid_locations.include?(location)
          raise ArgumentError, "Invalid parameter location: #{location}. Must be one of: #{valid_locations.join(', ')}"
        end

        location
      end

      def determine_required(required, location)
        return true if location == :path # Path parameters are always required

        required.nil? ? false : required
      end

      # Schema validation and type checking
      class Schema
        attr_reader :type, :format, :enum, :minimum, :maximum, :min_length, :max_length,
                    :pattern, :items, :default, :nullable

        def initialize(definition = {})
          @type = definition[:type] || :string
          @format = definition[:format]
          @enum = definition[:enum]
          @minimum = definition[:minimum]
          @maximum = definition[:maximum]
          @min_length = definition[:min_length]
          @max_length = definition[:max_length]
          @pattern = definition[:pattern]
          @items = definition[:items]
          @default = definition[:default]
          @nullable = definition[:nullable] || false
        end

        def validate(value)
          return true if value.nil? && @nullable
          return false if value.nil? && !@nullable

          case @type
          when :string
            validate_string(value)
          when :integer
            validate_integer(value)
          when :number
            validate_number(value)
          when :boolean
            validate_boolean(value)
          when :array
            validate_array(value)
          else
            true
          end
        end

        def validate_definition!
          valid_types = %i[string integer number boolean array object]
          raise ArgumentError, "Invalid schema type: #{@type}" unless valid_types.include?(@type)

          return unless @type == :array && @items.nil?

          raise ArgumentError, "Array type requires 'items' definition"
        end

        private

        def validate_string(value)
          return false unless value.is_a?(String)
          return false if @min_length && value.length < @min_length
          return false if @max_length && value.length > @max_length
          return false if @pattern && !value.match?(@pattern)
          return false if @enum && !@enum.include?(value)

          true
        end

        def validate_integer(value)
          int_value = value.is_a?(String) ? value.to_i : value
          return false unless int_value.is_a?(Integer)
          return false if @minimum && int_value < @minimum
          return false if @maximum && int_value > @maximum
          return false if @enum && !@enum.include?(int_value)

          true
        end

        def validate_number(value)
          num_value = value.is_a?(String) ? value.to_f : value
          return false unless num_value.is_a?(Numeric)
          return false if @minimum && num_value < @minimum
          return false if @maximum && num_value > @maximum
          return false if @enum && !@enum.include?(num_value)

          true
        end

        def validate_boolean(value)
          [true, false, 'true', 'false', '1', '0'].include?(value)
        end

        def validate_array(value)
          return false unless value.is_a?(Array)
          return false if @min_items && value.length < @min_items
          return false if @max_items && value.length > @max_items

          # Validate each item if items schema is provided
          if @items
            item_schema = Schema.new(@items)
            return false unless value.all? { |item| item_schema.validate(item) }
          end

          true
        end
      end
    end
  end
end
