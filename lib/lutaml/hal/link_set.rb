# frozen_string_literal: true

require 'lutaml/model'
require_relative 'model_register'

module Lutaml
  module Hal
    # HAL Link representation with realization capability
    class LinkSet < Lutaml::Model::Serializable
      attr_accessor :_global_register_id
    end
  end
end
