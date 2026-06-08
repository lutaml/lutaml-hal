# frozen_string_literal: true

require 'lutaml/model'

module Lutaml
  module Hal
    class Link < Lutaml::Model::Serializable
      attr_accessor :_global_register_id, :parent_resource

      attribute :href, :string
      attribute :title, :string
      attribute :name, :string
      attribute :templated, :boolean
      attribute :type, :string
      attribute :deprecation, :string
      attribute :profile, :string
      attribute :lang, :string

      def realize(register: nil, parent_resource: nil, force_refresh: false)
        effective_parent = parent_resource || @parent_resource

        register = find_register(register)
        raise "No register provided for link resolution (class: #{self.class}, href: #{href})" if register.nil?

        if !force_refresh && effective_parent && (embedded_content = check_embedded_content(effective_parent, register))
          register.cache_manager&.set(href, nil, embedded_content)
          return embedded_content
        end

        register.cache_manager&.invalidate(href) if force_refresh

        Hal.debug_log "Resolving link href: #{href} using register"
        register.resolve_and_cast(self, href)
      end

      private

      def check_embedded_content(parent_resource, register = nil)
        return nil unless parent_resource.is_a?(Resource) && parent_resource.embedded_data

        embedded_data = parent_resource.embedded_data
        return nil unless embedded_data

        embedded_data.each_value do |content|
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

        item.dig('_links', 'self', 'href') == href
      end

      def create_embedded_resource(embedded_item, _parent_resource, register = nil)
        register = find_register(register)
        return nil unless register

        href_path = href.sub(register.client.api_url, '') if register.client
        model_class = register.find_matching_model_class(href_path)
        return nil unless model_class

        resource = model_class.from_embedded(embedded_item, _global_register_id)
        register.mark_model_links_with_register(resource)
        resource
      end

      def find_register(explicit_register)
        return explicit_register if explicit_register

        register_id = _global_register_id
        return nil if register_id.nil?

        register = GlobalRegister.instance.get(register_id)
        if register.nil?
          raise 'GlobalRegister in use but unable to find the register. '\
            'Please provide a register to the `#realize` method to resolve the link'
        end

        register
      end
    end
  end
end
