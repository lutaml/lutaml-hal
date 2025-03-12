# frozen_string_literal: true

require_relative 'resource'

module Lutaml
  module Hal
    # Models the pagination of a collection of resources
    # This class is used to represent the pagination information
    # for a collection of resources in the HAL format.
    class Page < Resource
      attribute :page, :integer
      attribute :limit, :integer
      attribute :pages, :integer
      attribute :total, :integer

      key_value do
        map 'page', to: :page
        map 'limit', to: :limit
        map 'pages', to: :pages
        map 'total', to: :total
      end

      def self.inherited(subclass)
        super

        page_links_symbols = %i[self next prev first last]
        subclass_name = subclass.name
        subclass.class_eval do
          # Define common page links
          page_links_symbols.each do |link_symbol|
            hal_link link_symbol, key: link_symbol.to_s, realize_class: subclass_name
          end
        end
      end
    end
  end
end
