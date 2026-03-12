# frozen_string_literal: true

require 'singleton'

module Lutaml
  module Hal
    # Global register for model registers
    # This class is a singleton that manages the registration and retrieval of model registers.
    # It ensures that each model register is unique and provides a way to access them globally.
    #
    # @example
    #   global_register = GlobalRegister.instance
    #   global_register.register(:example, ExampleModelRegister.new)
    #   example_register = global_register.get(:example)
    class GlobalRegister
      include Singleton

      def initialize
        @model_registers = {}
      end

      def register(name, model_register)
        if @model_registers[name] && @model_registers[name] != model_register
          raise "Model register with name #{name} replacing another one" \
                " (#{@model_registers[name].inspect} vs #{model_register.inspect})"
        end

        @model_registers[name] = model_register
      end

      def get(name)
        raise "Model register with name #{name} not found" unless @model_registers[name]

        @model_registers[name]
      end

      def delete(name)
        return unless @model_registers[name]

        @model_registers.delete(name)
      end

      def unregister(name)
        delete(name)
      end

      # Cache management methods for all registered model registers
      def clear_all_caches
        @model_registers.each_value do |register|
          register.clear_cache if register.respond_to?(:clear_cache)
        end
      end

      def cache_stats
        stats = {}
        @model_registers.each do |name, register|
          if register.respond_to?(:cache_info)
            stats[name] = register.cache_info
          end
        end
        stats
      end

      def list_registers
        @model_registers.keys
      end
    end
  end
end
