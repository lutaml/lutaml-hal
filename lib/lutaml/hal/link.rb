# frozen_string_literal: true

require 'lutaml/model'
require_relative 'model_register'

module Lutaml
  module Hal
    # HAL Link representation with realization capability
    class Link < Lutaml::Model::Serializable
      # This is the model register that has fetched the origin of this link, and
      # will be used to resolve unless overriden in resource#realize()
      attr_accessor Hal::REGISTER_ID_ATTR_NAME.to_sym

      attribute :href, :string
      attribute :title, :string
      attribute :name, :string
      attribute :templated, :boolean
      attribute :type, :string
      attribute :deprecation, :string
      attribute :profile, :string
      attribute :lang, :string

      # Fetch the actual resource this link points to.
      # This method will use the global register according to the source of the Link object.
      # If the Link does not have a register, a register needs to be provided explicitly
      # via the `register:` parameter.
      def realize(register: nil)
        register = find_register(register)
        raise "No register provided for link resolution (class: #{self.class}, href: #{href})" if register.nil?

        Hal.debug_log "Resolving link href: #{href} using register"
        register.resolve_and_cast(self, href)
      end

      private

      def find_register(explicit_register)
        return explicit_register if explicit_register

        register_id = instance_variable_get("@#{Hal::REGISTER_ID_ATTR_NAME}")
        return nil if register_id.nil?

        register = Lutaml::Hal::GlobalRegister.instance.get(register_id)
        if register.nil?
          raise 'GlobalRegister in use but unable to find the register. '\
            'Please provide a register to the `#realize` method to resolve the link'
        end

        register
      end
    end
  end
end
