# frozen_string_literal: true

module Lutaml
  module Hal
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

        return unless subclass.name

        page_links_symbols = %i[self next prev first last up]
        subclass_name = subclass.name
        subclass.class_eval do
          page_links_symbols.each do |link_symbol|
            hal_link link_symbol, key: link_symbol.to_s, realize_class: subclass_name
          end
        end
      end

      def next
        return nil unless links.next

        links.next.realize
      end

      def prev
        return links.prev.realize if links.prev

        return nil if page <= 1

        prev_page_url = construct_page_url(page - 1)
        return nil unless prev_page_url

        register_name = _global_register_id
        return nil unless register_name

        hal_register = GlobalRegister.instance.get(register_name)
        return nil unless hal_register

        hal_register.resolve_and_cast(nil, prev_page_url)
      end

      def first
        return nil unless links.first

        links.first.realize
      end

      def last
        return nil unless links.last

        links.last.realize
      end

      def total_pages
        pages
      end

      def next?
        !links.next.nil?
      end

      def prev?
        !links.prev.nil?
      end

      def first?
        !links.first.nil?
      end

      def last?
        !links.last.nil?
      end

      def next_page
        links.next
      end

      def prev_page
        links.prev
      end

      def first_page
        links.first
      end

      def last_page
        links.last
      end

      private

      def construct_page_url(target_page)
        reference_url = links.next&.href || links.first&.href || links.last&.href
        return nil unless reference_url

        uri = URI.parse(reference_url)
        query_params = URI.decode_www_form(uri.query || '')

        query_params = query_params.reject { |key, _| key == 'page' }
        query_params << ['page', target_page.to_s]

        uri.query = URI.encode_www_form(query_params)
        uri.to_s
      end
    end
  end
end
