# frozen_string_literal: true

require 'lutaml/model'

module Lutaml
  module Hal
    class Resource < Lutaml::Model::Serializable
      attr_accessor :_global_register_id, :embedded_data

      def has_embedded?(key)
        embedded_data&.key?(key.to_s)
      end

      def get_embedded(key)
        embedded_data&.[](key.to_s)
      end

      def self.from_embedded(json_data, register_name = nil)
        instance = from_json(json_data.to_json)
        instance._global_register_id = register_name if register_name
        instance
      end

      class << self
        attr_accessor :link_definitions

        def inherited(subclass)
          super
          subclass.class_eval do
            init_links_definition
          end
        end

        def hal_link(attr_key,
                     key:,
                     realize_class:,
                     link_class: nil,
                     link_set_class: nil,
                     collection: false,
                     type: :link)
          raise ArgumentError, 'realize_class parameter is required' if realize_class.nil?

          attribute_name = attr_key.to_sym

          Hal.debug_log "Defining HAL link for `#{attr_key}` with realize class `#{realize_class}`"

          realize_class_name = case realize_class
                               when Class
                                 realize_class.name.split('::').last
                               when String
                                 realize_class
                               else
                                 raise ArgumentError,
                                       "realize_class must be a Class or String, got #{realize_class.class}"
                               end

          link_set_klass = link_set_class || create_link_set_class

          raise 'Failed to create LinkSet class' if link_set_klass.nil?

          link_klass = link_class || create_link_class(realize_class_name)

          unless link_set_class
            link_set_klass.class_eval do
              if collection
                attribute attribute_name, link_klass, collection: true
              else
                attribute attribute_name, link_klass
              end

              key_value do
                map key, to: attribute_name
              end
            end
          end

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

        def get_link_set_class
          create_link_set_class
        end

        def create_link_set_class
          LinkSetClassFactory.create_for(self)
        end

        def init_links_definition
          @link_definitions = {}
        end

        def create_link_class(realize_class_name)
          LinkClassFactory.create_for(self, realize_class_name)
        end
      end
    end
  end
end
