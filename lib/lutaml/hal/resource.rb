# frozen_string_literal: true

require 'lutaml/model'
require_relative 'link'

module Lutaml
  module Hal
    # Resource class for all HAL resources
    class Resource < Lutaml::Model::Serializable
      # This is the model register that has fetched this resource, and
      # will be used to resolve links unless overriden in resource#realize()
      attr_accessor Hal::REGISTER_ID_ATTR_NAME.to_sym

      class << self
        attr_accessor :link_definitions

        # Callback for when a subclass is created
        def inherited(subclass)
          super
          subclass.class_eval do
            create_link_set_class
            init_links_definition
          end
        end

        # The developer defines a link to another resource
        # The "key" is the name of the attribute in the JSON
        # The "realize_class" is the class to be realized
        # The "collection" is a boolean indicating if the link
        # is a collection of resources or a single resource
        # The "type" is the type of the link (default is :link, can be :resource)
        def hal_link(attr_key,
                     key:,
                     realize_class:,
                     link_class: nil,
                     link_set_class: nil,
                     collection: false,
                     type: :link)
          # Use the provided "key" as the attribute name
          attribute_name = attr_key.to_sym

          Hal.debug_log "Defining HAL link for `#{attr_key}` with realize class `#{realize_class}`"

          # Create a dynamic Link subclass name based on "realize_class", the
          # class to realize for a Link object, if `link_class:` is not provided.
          link_klass = link_class || create_link_class(realize_class)

          # Create a dynamic LinkSet class if `link_set_class:` is not provided.
          unless link_set_class
            link_set_klass = link_set_class || get_link_set_class
            link_set_klass.class_eval do
              # Declare the corresponding lutaml-model attribute
              attribute attribute_name, link_klass, collection: collection

              # Define the mapping for the attribute
              key_value do
                map key, to: attribute_name
              end
            end
          end

          # Create a new link definition for future reference
          link_def = {
            attribute_name: attribute_name,
            key: attr_key,
            klass: link_klass,
            collection: collection,
            type: type
          }

          @link_definitions ||= {}
          @link_definitions[key] = link_def
        end

        # This method obtains the Links class that holds the Link classes
        def get_link_set_class
          parent_klass_name = name.split('::')[0..-2].join('::')
          child_klass_name = "#{name.split('::').last}LinkSet"
          klass_name = [parent_klass_name, child_klass_name].join('::')

          raise unless Object.const_defined?(klass_name)

          Object.const_get(klass_name)
        end

        private

        # The "links" class holds the `_links` object which contains
        # the resource-linked Link classes
        def create_link_set_class
          parent_klass_name = name.split('::')[0..-2].join('::')
          child_klass_name = "#{name.split('::').last}LinkSet"
          klass_name = [parent_klass_name, child_klass_name].join('::')

          Hal.debug_log "Creating link set class #{klass_name}"

          # Check if the LinkSet class is already defined, return if so
          return Object.const_get(klass_name) if Object.const_defined?(klass_name)

          # Define the LinkSet class dynamically as a normal Lutaml::Model class
          # since it is not a Resource.
          klass = Class.new(Lutaml::Hal::LinkSet)
          parent_klass = !parent_klass_name.empty? ? Object.const_get(parent_klass_name) : Object
          parent_klass.const_set(child_klass_name, klass)

          # Define the LinkSet class with mapping inside the current class
          class_eval do
            attribute :links, klass
            key_value do
              map '_links', to: :links
            end
          end
        end

        def init_links_definition
          @link_definitions = {}
        end

        # This is a Link class that helps us realize the targeted class
        def create_link_class(realize_class_name)
          parent_klass_name = name.split('::')[0..-2].join('::')
          child_klass_name = "#{realize_class_name.split('::').last}Link"
          klass_name = [parent_klass_name, child_klass_name].join('::')

          Hal.debug_log "Creating link class #{klass_name} for #{realize_class_name}"

          return Object.const_get(klass_name) if Object.const_defined?(klass_name)

          # Define the link class dynamically
          klass = Class.new(Link) do
            # Define the link class with the specified key and class
            attribute :type, :string, default: realize_class_name
          end

          parent_klass = !parent_klass_name.empty? ? Object.const_get(parent_klass_name) : Object
          parent_klass.const_set(child_klass_name, klass)

          klass
        end
      end
    end
  end
end
