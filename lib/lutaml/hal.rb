# frozen_string_literal: true

require 'lutaml/model'

module Lutaml
  # HAL implementation for Lutaml
  module Hal
  end
end

require_relative 'hal/version'
require_relative 'hal/errors'
require_relative 'hal/link'
require_relative 'hal/resource'
require_relative 'hal/page'
require_relative 'hal/model_register'
require_relative 'hal/client'
