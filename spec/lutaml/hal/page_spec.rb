# frozen_string_literal: true

require_relative '../../spec_helper'

module PageSpec
  class PageModel < Lutaml::Hal::Page
    attribute :page, :integer
    attribute :limit, :integer
    attribute :pages, :integer
    attribute :total, :integer

    hal_link :self, key: 'self', realize_class: 'PageSpec::PageModel'
    hal_link :next, key: 'next', realize_class: 'PageSpec::PageModel'
    hal_link :prev, key: 'prev', realize_class: 'PageSpec::PageModel'
    hal_link :first, key: 'first', realize_class: 'PageSpec::PageModel'
    hal_link :last, key: 'last', realize_class: 'PageSpec::PageModel'
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

  let(:register) do
    Lutaml::Hal::ModelRegister.new(client: client).tap do |r|
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
  end
end
