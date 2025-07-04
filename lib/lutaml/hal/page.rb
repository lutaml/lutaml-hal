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

        # Skip automatic link creation for anonymous classes (used in tests)
        return unless subclass.name

        page_links_symbols = %i[self next prev first last up]
        subclass_name = subclass.name
        subclass.class_eval do
          # Define common page links
          page_links_symbols.each do |link_symbol|
            hal_link link_symbol, key: link_symbol.to_s, realize_class: subclass_name
          end
        end
      end

      # Returns the next page of results, or nil if on the last page
      #
      # @return [Object, nil] The next page instance or nil
      def next
        return nil unless links.next

        links.next.realize
      end

      # Returns the previous page of results, or nil if on the first page
      #
      # @return [Object, nil] The previous page instance or nil
      def prev
        # If the API provides a prev link, use it
        return links.prev.realize if links.prev

        # If we're on page 1, there's no previous page
        return nil if page <= 1

        # Construct the previous page URL manually
        prev_page_url = construct_page_url(page - 1)
        return nil unless prev_page_url

        # Use the HAL register to fetch the previous page
        register_name = instance_variable_get("@#{Lutaml::Hal::REGISTER_ID_ATTR_NAME}")
        return nil unless register_name

        hal_register = Lutaml::Hal::GlobalRegister.instance.get(register_name)
        return nil unless hal_register

        hal_register.resolve_and_cast(nil, prev_page_url)
      end

      # Returns the first page of results
      #
      # @return [Object, nil] The first page instance or nil
      def first
        return nil unless links.first

        links.first.realize
      end

      # Returns the last page of results
      #
      # @return [Object, nil] The last page instance or nil
      def last
        return nil unless links.last

        links.last.realize
      end

      # Returns the total number of pages
      #
      # @return [Integer] The total number of pages
      def total_pages
        pages
      end

      # Checks if there is a next page available
      #
      # @return [Boolean] true if next page exists, false otherwise
      def next?
        !links.next.nil?
      end

      # Checks if there is a previous page available
      #
      # @return [Boolean] true if previous page exists, false otherwise
      def prev?
        !links.prev.nil?
      end

      # Checks if there is a first page link available
      #
      # @return [Boolean] true if first page link exists, false otherwise
      def first?
        !links.first.nil?
      end

      # Checks if there is a last page link available
      #
      # @return [Boolean] true if last page link exists, false otherwise
      def last?
        !links.last.nil?
      end

      # Returns the next page link, or nil if on the last page
      #
      # @return [Object, nil] The next page link or nil
      def next_page
        links.next
      end

      # Returns the previous page link, or nil if on the first page
      #
      # @return [Object, nil] The previous page link or nil
      def prev_page
        links.prev
      end

      # Returns the first page link
      #
      # @return [Object, nil] The first page link or nil
      def first_page
        links.first
      end

      # Returns the last page link
      #
      # @return [Object, nil] The last page link or nil
      def last_page
        links.last
      end

      private

      # Constructs a URL for a specific page based on the current page's URL pattern
      #
      # @param target_page [Integer] The page number to construct URL for
      # @return [String, nil] The constructed URL or nil if unable to construct
      def construct_page_url(target_page)
        # Try to get a reference URL from next, first, or last links
        reference_url = links.next&.href || links.first&.href || links.last&.href
        return nil unless reference_url

        # Parse the reference URL and modify the page parameter
        uri = URI.parse(reference_url)
        query_params = URI.decode_www_form(uri.query || '')

        # Update the page parameter
        query_params = query_params.reject { |key, _| key == 'page' }
        query_params << ['page', target_page.to_s]

        # Reconstruct the URL
        uri.query = URI.encode_www_form(query_params)
        uri.to_s
      end
    end
  end
end
