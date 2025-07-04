# frozen_string_literal: true

require_relative 'link_set'

module Lutaml
  module Hal
    # Factory class responsible for creating dynamic LinkSet classes
    class LinkSetClassFactory
      def self.create_for(resource_class)
        new(resource_class).create
      end

      def initialize(resource_class)
        @resource_class = resource_class
      end

      def create
        return create_anonymous_link_set_class if anonymous_class?

        class_names = build_class_names
        return existing_class(class_names[:full_name]) if class_exists?(class_names[:full_name])

        klass = create_named_link_set_class(class_names)
        register_constant(klass, class_names)
        setup_resource_mapping(klass)
        klass
      end

      private

      def anonymous_class?
        @resource_class.name.nil?
      end

      def create_anonymous_link_set_class
        klass = Class.new(LinkSet)
        setup_resource_mapping(klass)
        klass
      end

      def create_named_link_set_class(class_names)
        Hal.debug_log "Creating link set class #{class_names[:full_name]}"
        Class.new(LinkSet)
      end

      def build_class_names
        parent_namespace = @resource_class.name.split('::')[0..-2].join('::')
        child_class_name = "#{@resource_class.name.split('::').last}LinkSet"
        full_class_name = [parent_namespace, child_class_name].reject(&:empty?).join('::')

        {
          parent_namespace: parent_namespace,
          child_name: child_class_name,
          full_name: full_class_name
        }
      end

      def class_exists?(class_name)
        Object.const_defined?(class_name)
      end

      def existing_class(class_name)
        Object.const_get(class_name)
      end

      def register_constant(klass, class_names)
        parent_klass = resolve_parent_class(class_names[:parent_namespace])
        parent_klass.const_set(class_names[:child_name], klass)
      end

      def resolve_parent_class(parent_namespace)
        return Object if parent_namespace.empty?

        begin
          Object.const_get(parent_namespace)
        rescue NameError
          Object
        end
      end

      def setup_resource_mapping(link_set_class)
        # Define the LinkSet class with mapping inside the resource class
        @resource_class.class_eval do
          attribute :links, link_set_class
          key_value do
            map '_links', to: :links
          end
        end
      end
    end
  end
end
