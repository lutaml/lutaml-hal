# frozen_string_literal: true

require_relative '../../spec_helper'

module PageSpec
  class PageModel < Lutaml::Hal::Page
  end
end

RSpec.describe Lutaml::Hal::Page do
  let(:api_url) { 'https://api.example.com' }

  let(:stubs) { Faraday::Adapter::Test::Stubs.new }

  let(:connection) do
    Faraday.new do |builder|
      builder.request :json
      builder.response :json, content_type: /\bjson$/
      builder.adapter :test, stubs
    end
  end

  let(:client) do
    Lutaml::Hal::Client.new(
      api_url: api_url,
      connection: connection
    )
  end

  let(:model_register) do
    Lutaml::Hal::ModelRegister.new(name: :page_spec, client: client).tap do |r|
      r.add_endpoint(
        id: :pages_index,
        type: :index,
        url: '/sample_pages',
        model: PageSpec::PageModel
      )
      r.add_endpoint(
        id: :page_resource,
        type: :resource,
        url: '/sample_pages/{page}',
        model: PageSpec::PageModel
      )
    end
  end

  let(:global_register) do
    Lutaml::Hal::GlobalRegister.instance.tap do |r|
      r.delete(:page_spec)
      r.register(:page_spec, model_register)
    end
  end

  let(:register) do
    global_register.get(:page_spec)
  end

  let(:response_page_1) do
    {
      'page' => 1,
      'limit' => 10,
      'pages' => 5,
      'total' => 45,
      '_links' => {
        'first' => { 'href' => '/sample_pages/1' },
        'next' => { 'href' => '/sample_pages/2' },
        'last' => { 'href' => '/sample_pages/5' }
      }
    }
  end

  let(:response_page_2) do
    {
      'page' => 2,
      'limit' => 10,
      'pages' => 5,
      'total' => 45,
      '_links' => {
        'first' => { 'href' => '/sample_pages/1' },
        'prev' => { 'href' => '/sample_pages/1' },
        'next' => { 'href' => '/sample_pages/3' },
        'last' => { 'href' => '/sample_pages/5' }
      }
    }
  end

  let(:response_page_5) do
    {
      'page' => 5,
      'limit' => 5,
      'pages' => 5,
      'total' => 45,
      '_links' => {
        'first' => { 'href' => '/sample_pages/1' },
        'prev' => { 'href' => '/sample_pages/4' },
        'next' => { 'href' => '/sample_pages/6' },
        'last' => { 'href' => '/sample_pages/5' }
      }
    }
  end

  context 'parsing' do
    it 'maps attributes correctly' do
      page = PageSpec::PageModel.from_json(response_page_1.to_json)
      expect(page.page).to eq(1)
      expect(page.limit).to eq(10)
      expect(page.pages).to eq(5)
      expect(page.total).to eq(45)
    end

    it 'maps links correctly' do
      page = PageSpec::PageModel.from_json(response_page_1.to_json)
      expect(page.links.next.href).to eq('/sample_pages/2')
      expect(page.links.last.href).to eq('/sample_pages/5')
      expect(page.links.first.href).to eq('/sample_pages/1')
    end
  end

  context 'pagination methods' do
    let(:page_1) { PageSpec::PageModel.from_json(response_page_1.to_json) }
    let(:page_2) { PageSpec::PageModel.from_json(response_page_2.to_json) }
    let(:page_5) { PageSpec::PageModel.from_json(response_page_5.to_json) }

    describe '#total_pages' do
      it 'returns the total number of pages' do
        expect(page_1.total_pages).to eq(5)
        expect(page_2.total_pages).to eq(5)
        expect(page_5.total_pages).to eq(5)
      end
    end

    describe '#page' do
      it 'returns the current page number' do
        expect(page_1.page).to eq(1)
        expect(page_2.page).to eq(2)
        expect(page_5.page).to eq(5)
      end
    end

    describe '#total' do
      it 'returns the total number of items' do
        expect(page_1.total).to eq(45)
        expect(page_2.total).to eq(45)
        expect(page_5.total).to eq(45)
      end
    end

    describe '#has_next?' do
      it 'returns true when next link exists' do
        expect(page_1.has_next?).to be true
        expect(page_2.has_next?).to be true
      end

      it 'returns false when next link does not exist' do
        page_without_next = PageSpec::PageModel.from_json({
          'page' => 5,
          'pages' => 5,
          '_links' => { 'prev' => { 'href' => '/sample_pages/4' } }
        }.to_json)
        expect(page_without_next.has_next?).to be false
      end
    end

    describe '#has_prev?' do
      it 'returns true when prev link exists' do
        expect(page_2.has_prev?).to be true
        expect(page_5.has_prev?).to be true
      end

      it 'returns false when prev link does not exist' do
        expect(page_1.has_prev?).to be false
      end
    end

    describe '#has_first?' do
      it 'returns true when first link exists' do
        expect(page_1.has_first?).to be true
        expect(page_2.has_first?).to be true
        expect(page_5.has_first?).to be true
      end
    end

    describe '#has_last?' do
      it 'returns true when last link exists' do
        expect(page_1.has_last?).to be true
        expect(page_2.has_last?).to be true
        expect(page_5.has_last?).to be true
      end
    end
  end

  context 'when making API requests' do
    let!(:url_stubs) do
      stubs.get('/sample_pages') do
        [200, { 'Content-Type' => 'application/json' }, response_page_1.to_json]
      end

      stubs.get('/sample_pages/1') do
        [200, { 'Content-Type' => 'application/json' }, response_page_1.to_json]
      end

      stubs.get('/sample_pages/2') do
        [200, { 'Content-Type' => 'application/json' }, response_page_2.to_json]
      end

      stubs.get('/sample_pages/3') do
        [200, { 'Content-Type' => 'application/json' }, {
          'page' => 3,
          'limit' => 10,
          'pages' => 5,
          'total' => 45,
          '_links' => {
            'first' => { 'href' => '/sample_pages/1' },
            'prev' => { 'href' => '/sample_pages/2' },
            'next' => { 'href' => '/sample_pages/4' },
            'last' => { 'href' => '/sample_pages/5' }
          }
        }.to_json]
      end

      stubs.get('/sample_pages/4') do
        [200, { 'Content-Type' => 'application/json' }, {
          'page' => 4,
          'limit' => 10,
          'pages' => 5,
          'total' => 45,
          '_links' => {
            'first' => { 'href' => '/sample_pages/1' },
            'prev' => { 'href' => '/sample_pages/3' },
            'next' => { 'href' => '/sample_pages/5' },
            'last' => { 'href' => '/sample_pages/5' }
          }
        }.to_json]
      end

      stubs.get('/sample_pages/5') do
        [200, { 'Content-Type' => 'application/json' }, response_page_5.to_json]
      end
    end

    let(:api_url) { 'https://api.example.com' }

    it 'retrieves the first page' do
      register.fetch(:pages_index)
      page_2 = register.fetch(:page_resource, page: 2)
      expect(page_2).to be_a(PageSpec::PageModel)
      expect(page_2.page).to eq(2)
      expect(page_2.limit).to eq(10)
      expect(page_2.pages).to eq(5)
      expect(page_2.total).to eq(45)
      expect(page_2.links.prev.href).to eq('/sample_pages/1')
    end

    it 'retrieves the second page' do
      page_2 = register.fetch(:page_resource, page: 2)
      expect(page_2).to be_a(PageSpec::PageModel)
      expect(page_2.page).to eq(2)
      expect(page_2.limit).to eq(10)
      expect(page_2.pages).to eq(5)
      expect(page_2.total).to eq(45)
      expect(page_2.links.prev.href).to eq('/sample_pages/1')
    end

    it 'retrieves the last page' do
      page_5 = register.fetch(:page_resource, page: 5)
      expect(page_5).to be_a(PageSpec::PageModel)
      expect(page_5.page).to eq(5)
      expect(page_5.limit).to eq(5)
      expect(page_5.pages).to eq(5)
      expect(page_5.total).to eq(45)
      expect(page_5.links.prev.href).to eq('/sample_pages/4')
    end

    describe 'pagination navigation methods' do
      before do
        # Set up the page with the register for navigation
        @page_1 = register.fetch(:pages_index)
        @page_1.instance_variable_set(:@register, register)
      end

      describe '#next_page' do
        it 'returns the next page link when available' do
          next_link = @page_1.next_page
          expect(next_link).not_to be_nil
          expect(next_link.href).to eq('/sample_pages/2')
        end

        it 'returns nil when no next page exists' do
          page_5 = register.fetch(:page_resource, page: 5)

          # Mock the response to not have a next link
          allow(page_5.links).to receive(:next).and_return(nil)
          expect(page_5.next_page).to be_nil
        end

        it 'can realize the next page' do
          next_link = @page_1.next_page
          next_page = next_link.realize
          expect(next_page).to be_a(PageSpec::PageModel)
          expect(next_page.page).to eq(2)
        end
      end

      describe '#prev_page' do
        it 'returns the previous page link when available' do
          page_2 = register.fetch(:page_resource, page: 2)

          prev_link = page_2.prev_page
          expect(prev_link).not_to be_nil
          expect(prev_link.href).to eq('/sample_pages/1')
        end

        it 'returns nil when no previous page exists' do
          expect(@page_1.prev_page).to be_nil
        end

        it 'can realize the previous page' do
          page_2 = register.fetch(:page_resource, page: 2)

          prev_link = page_2.prev_page
          prev_page = prev_link.realize
          expect(prev_page).to be_a(PageSpec::PageModel)
          expect(prev_page.page).to eq(1)
        end
      end

      describe '#first_page' do
        it 'returns the first page link when available' do
          page_2 = register.fetch(:page_resource, page: 2)

          first_link = page_2.first_page
          expect(first_link).not_to be_nil
          expect(first_link.href).to eq('/sample_pages/1')
        end

        it 'can realize the first page' do
          page_2 = register.fetch(:page_resource, page: 2)

          first_link = page_2.first_page
          first_page = first_link.realize
          expect(first_page).to be_a(PageSpec::PageModel)
          expect(first_page.page).to eq(1)
        end
      end

      describe '#last_page' do
        it 'returns the last page link when available' do
          last_link = @page_1.last_page
          expect(last_link).not_to be_nil
          expect(last_link.href).to eq('/sample_pages/5')
        end

        it 'can realize the last page' do
          last_link = @page_1.last_page
          last_page = last_link.realize
          expect(last_page).to be_a(PageSpec::PageModel)
          expect(last_page.page).to eq(5)
        end
      end
    end
  end
end
