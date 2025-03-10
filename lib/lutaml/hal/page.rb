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
    end
  end
end
