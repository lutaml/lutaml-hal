# frozen_string_literal: true

module Lutaml
  module Hal
    # Module that provides lazy type resolution functionality for dynamically created classes
    # This solves the class loading order problem where HAL type names would be inconsistent
    # depending on file loading order.
    module TypeResolver
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        attr_reader :realize_class_name

        def setup_type_resolution(realize_class_name)
          @realize_class_name = realize_class_name
          @resolved_type_name = nil
        end

        # Lazy resolution at class level - only happens once per class
        def resolved_type_name
          @resolved_type_name ||= resolve_type_name(@realize_class_name)
        end

        private

        def resolve_type_name(class_name_string)
          return class_name_string unless class_name_string.is_a?(String)

          # Try simple name first (preferred for HAL output)
          begin
            Object.const_get(class_name_string)
            class_name_string
          rescue NameError
            # Try within current module namespace
            begin
              current_module = name.split('::')[0..-2].join('::')
              unless current_module.empty?
                Object.const_get(current_module).const_get(class_name_string)
                return class_name_string
              end
            rescue NameError
              # Continue to fallback
            end

            # Fallback: return the original string (may be fully qualified)
            class_name_string
          end
        end
      end

      # Override the type getter to use class-level lazy resolution
      def type
        @type || self.class.resolved_type_name
      end
    end
  end
end
