# frozen_string_literal: true

require 'lutaml/model'
require_relative 'model_register'

module Lutaml
  module Hal
    # HAL Link representation with realization capability
    class Link < Lutaml::Model::Serializable
      attribute :href, :string
      attribute :title, :string
      attribute :name, :string
      attribute :templated, :boolean
      attribute :type, :string
      attribute :deprecation, :string
      attribute :profile, :string
      attribute :lang, :string

      # Fetch the actual resource this link points to
      def realize(register)
        register.resolve_and_cast(href)
      end
    end
  end
end
