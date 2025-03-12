# frozen_string_literal: true

require 'lutaml/model'
require_relative 'model_register'

module Lutaml
  module Hal
    # HAL Link representation with realization capability
    class LinkSet < Lutaml::Model::Serializable
      attr_accessor Hal::REGISTER_ID_ATTR_NAME.to_sym
    end
  end
end
