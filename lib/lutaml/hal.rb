# frozen_string_literal: true

require 'lutaml/model'

module Lutaml
  # HAL implementation for Lutaml
  module Hal
    REGISTER_ID_ATTR_NAME = '_global_register_id'

    def self.debug_log(message)
      puts "[Lutaml::Hal] DEBUG: #{message}" if ENV['DEBUG_API']
    end
  end
end

require_relative 'hal/version'
require_relative 'hal/errors'
require_relative 'hal/rate_limiter'
require_relative 'hal/endpoint_parameter'
require_relative 'hal/link'
require_relative 'hal/link_set'
require_relative 'hal/resource'
require_relative 'hal/page'
require_relative 'hal/global_register'
require_relative 'hal/model_register'
require_relative 'hal/client'
