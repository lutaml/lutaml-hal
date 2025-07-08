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

      # Store reference to parent resource for automatic embedded content detection
      attr_accessor :parent_resource

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
      def realize(register: nil, parent_resource: nil)
        # Use provided parent_resource or fall back to stored parent_resource
        effective_parent = parent_resource || @parent_resource

        # First check if embedded content is available
        if effective_parent && (embedded_content = check_embedded_content(effective_parent, register))
          return embedded_content
        end

        register = find_register(register)
        raise "No register provided for link resolution (class: #{self.class}, href: #{href})" if register.nil?

        Hal.debug_log "Resolving link href: #{href} using register"
        register.resolve_and_cast(self, href)
      end

      private

      def check_embedded_content(parent_resource, register = nil)
        return nil unless parent_resource.respond_to?(:embedded_data)

        # Try to find embedded content that matches this link
        # Look for embedded content by matching the link's key or href pattern
        embedded_data = parent_resource.embedded_data
        return nil unless embedded_data

        # Try to find matching embedded content
        # This is a simplified approach - in practice, you might need more sophisticated matching
        embedded_data.each_value do |content|
          # If content is an array, check if any item matches this link
          if content.is_a?(Array)
            matching_item = content.find { |item| matches_embedded_item?(item) }
            return create_embedded_resource(matching_item, parent_resource, register) if matching_item
          elsif content.is_a?(Hash) && matches_embedded_item?(content)
            return create_embedded_resource(content, parent_resource, register)
          end
        end

        nil
      end

      def matches_embedded_item?(item)
        return false unless item.is_a?(Hash)

        # Check if the embedded item's self link matches this link's href
        item_self_link = item.dig('_links', 'self', 'href')
        return true if item_self_link == href

        # Additional matching logic could be added here
        false
      end

      def create_embedded_resource(embedded_item, _parent_resource, register = nil)
        # Get the register to determine the appropriate model class
        register = find_register(register)
        return nil unless register

        # Try to find the model class for this href
        href_path = href.sub(register.client.api_url, '') if register.client
        model_class = register.send(:find_matching_model_class, href_path)
        return nil unless model_class

        # Create the resource from embedded data
        resource = model_class.from_embedded(embedded_item, instance_variable_get("@#{Hal::REGISTER_ID_ATTR_NAME}"))
        register.send(:mark_model_links_with_register, resource)
        resource
      end

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
