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
    end
  end
end
