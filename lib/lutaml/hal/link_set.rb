# frozen_string_literal: true

require 'lutaml/model'

module Lutaml
  module Hal
    class LinkSet < Lutaml::Model::Serializable
      attr_accessor :_global_register_id
    end
  end
end
