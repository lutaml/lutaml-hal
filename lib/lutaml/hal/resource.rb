# frozen_string_literal: true

require 'lutaml/model'
require_relative 'link'
require_relative 'link_class_factory'
require_relative 'link_set_class_factory'

module Lutaml
  module Hal
    # Resource class for all HAL resources
    class Resource < Lutaml::Model::Serializable
      # This is the model register that has fetched this resource, and
      # will be used to resolve links unless overriden in resource#realize()
      attr_accessor Hal::REGISTER_ID_ATTR_NAME.to_sym

      # Access embedded data if available
      def embedded_data
        @_embedded
      end

      # Check if embedded data exists for a given key
      def has_embedded?(key)
        embedded_data&.key?(key.to_s)
      end

      # Get embedded content for a specific key
      def get_embedded(key)
        embedded_data&.[](key.to_s)
      end

      # Create a resource instance from embedded JSON data
      def self.from_embedded(json_data, register_name = nil)
        instance = from_json(json_data.to_json)
        instance.instance_variable_set("@#{Hal::REGISTER_ID_ATTR_NAME}", register_name) if register_name
        instance
      end

      class << self
        attr_accessor :link_definitions

        # Callback for when a subclass is created
        def inherited(subclass)
          super
          subclass.class_eval do
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
          # Validate required parameters
          raise ArgumentError, 'realize_class parameter is required' if realize_class.nil?

          # Use the provided "key" as the attribute name
          attribute_name = attr_key.to_sym

          Hal.debug_log "Defining HAL link for `#{attr_key}` with realize class `#{realize_class}`"

          # Normalize realize_class to a string for consistent handling
          # Support both Class objects (when autoload is available) and strings (for delayed interpretation)
          realize_class_name = case realize_class
                               when Class
                                 realize_class.name.split('::').last # Use simple name from actual class
                               when String
                                 realize_class # Use string as-is for lazy resolution
                               else
                                 raise ArgumentError,
                                       "realize_class must be a Class or String, got #{realize_class.class}"
                               end

          # Create a dynamic LinkSet class if `link_set_class:` is not provided.
          # This must happen BEFORE creating the Link class to ensure proper order
          link_set_klass = link_set_class || create_link_set_class

          # Ensure it was actually created
          raise 'Failed to create LinkSet class' if link_set_klass.nil?

          # Create a dynamic Link subclass name based on "realize_class", the
          # class to realize for a Link object, if `link_class:` is not provided.
          link_klass = link_class || create_link_class(realize_class_name)

          # Now add the link to the LinkSet class
          unless link_set_class
            link_set_klass.class_eval do
              # Declare the corresponding lutaml-model attribute
              # Pass collection parameter correctly to the attribute definition
              if collection
                attribute attribute_name, link_klass, collection: true
              else
                attribute attribute_name, link_klass
              end

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
        # Delegates to LinkSetClassFactory for simplified implementation
        def get_link_set_class
          create_link_set_class
        end

        # The "links" class holds the `_links` object which contains
        # the resource-linked Link classes
        # Delegates to LinkSetClassFactory for simplified implementation
        def create_link_set_class
          LinkSetClassFactory.create_for(self)
        end

        def init_links_definition
          @link_definitions = {}
        end

        # Creates a Link class that helps us realize the targeted class
        # Delegates to LinkClassFactory for simplified implementation
        def create_link_class(realize_class_name)
          LinkClassFactory.create_for(self, realize_class_name)
        end
      end
    end
  end
end
