# frozen_string_literal: true

require 'lutaml-hal'
require 'faraday'

module IntegrationSpec
  # Specification methods

  class SpecificationIndex < Lutaml::Hal::Resource
    hal_link :self, key: 'self', realize_class: 'SpecificationIndex'
    hal_link :next, key: 'next', realize_class: 'SpecificationIndex'
    hal_link :prev, key: 'prev', realize_class: 'SpecificationIndex'
    hal_link :first, key: 'first', realize_class: 'SpecificationIndex'
    hal_link :last, key: 'last', realize_class: 'SpecificationIndex'
    hal_link :specifications, key: 'specifications', realize_class: 'Specification', collection: true
  end

  class Specification < Lutaml::Hal::Resource
    attribute :shortlink, :string
    attribute :description, :string
    attribute :title, :string
    attribute :href, :string
    attribute :shortname, :string
    attribute :editor_draft, :string
    attribute :series_version, :string

    hal_link :self, key: 'self', realize_class: 'Specification'

    key_value do
      %i[
        shortlink
        description
        title
        href
        shortname
        editor_draft
        series_version
      ].each do |key|
        map key.to_s.tr('_', '-'), to: key
      end
    end
  end
end

RSpec.describe 'Lutaml::Hal::IntegrationSpec' do
  let(:api_url) { 'https://api.w3.org' }

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
    Lutaml::Hal::ModelRegister.new(name: :integration_spec, client: client).tap do |r|
      r.add_endpoint(
        id: :spec_index,
        type: :index,
        url: '/specifications',
        model: IntegrationSpec::SpecificationIndex
      )
      r.add_endpoint(
        id: :spec_resource,
        type: :resource,
        url: '/specifications/{id}',
        model: IntegrationSpec::Specification
      )
    end
  end

  let(:global_register) do
    Lutaml::Hal::GlobalRegister.instance.tap do |r|
      r.delete(:integration_spec)
      r.register(:integration_spec, model_register)
    end
  end

  let(:register) do
    global_register.get(:integration_spec)
  end

  let(:index_response) do
    { 'page' => 1,
      'limit' => 100,
      'pages' => 17,
      'total' => 1624,
      '_links' =>
  { 'specifications' =>
    [{ 'href' =>
       'https://api.w3.org/specifications/png-2',
       'title' =>
       'Portable Network Graphics (PNG) Specification (Second Edition)' },
     { 'href' =>
       'https://api.w3.org/specifications/compactHTML-19980209',
       'title' =>
       'Compact HTML for Small Information Appliances' },
     { 'href' =>
       'https://api.w3.org/specifications/ATAG10',
       'title' =>
       'Authoring Tool Accessibility Guidelines 1.0' },
     { 'href' =>
       'https://api.w3.org/specifications/authentform',
       'title' =>
       'User Agent Authentication Forms' },
     { 'href' =>
       'https://api.w3.org/specifications/CSS1',
       'title' =>
       'Cascading Style Sheets, level 1' }] } }
  end

  let(:instance_response) do
    {
      'shortlink' => 'https://www.w3.org/TR/PNG/',
      'description' => <<~EOL,
        <p>This document describes PNG (Portable Network Graphics), an extensible
        file format for the lossless, portable, well-compressed storage of raster
        images. PNG provides a patent-free replacement for GIF and can also replace
        many common uses of TIFF. Indexed-color, grayscale, and truecolor images
        are supported, plus an optional alpha channel. Sample depths range from 1
        to 16 bits.</p>\r\n<p>PNG is designed to work well in online viewing
        applications, such as the World Wide Web, so it is fully streamable with
        a progressive display option. PNG is robust, providing both full file
        integrity checking and simple detection of common transmission errors.
        Also, PNG can store gamma and chromaticity data for improved color matching
        on heterogeneous platforms.</p>\r\n<p>This specification defines an
        Internet Media Type image/png.</p>
      EOL
      'title' => 'Portable Network Graphics (PNG) Specification (Second Edition)',
      'shortname' => 'png-2',
      'editor-draft' => 'https://w3c.github.io/png/',
      '_links' => {
        'self' => {
          'href' => 'https://api.w3.org/specifications/png-2'
        },
        'version-history' => {
          'href' => 'https://api.w3.org/specifications/png-2/versions'
        },
        'first-version' => {
          'href' => 'https://api.w3.org/specifications/png-2/versions/20030520',
          'title' => 'Proposed Recommendation'
        },
        'latest-version' => {
          'href' => 'https://api.w3.org/specifications/png-2/versions/20031110',
          'title' => 'Recommendation'
        },
        'series' => {
          'href' => 'https://api.w3.org/specification-series/png'
        }
      }
    }
  end

  context 'when making API requests' do
    let!(:url_stubs) do
      stubs.get('/specifications') do
        [200, { 'Content-Type' => 'application/json' }, index_response.to_json]
      end

      stubs.get('/specifications/png-2') do
        [200, { 'Content-Type' => 'application/json' }, instance_response.to_json]
      end
    end

    it 'retrieves specifications successfully' do
      index = register.fetch(:spec_index)
      expect(index).to be_a(Lutaml::Hal::Resource)

      expect(index.links).to be_a(Lutaml::Model::Serializable)
      expect(index.links.specifications).to all(be_a(Lutaml::Hal::Link))

      first_specification_link = index.links.specifications.first
      fs_implied = first_specification_link.realize
      first_specification = first_specification_link.realize(register: register)

      # Verify the first specification realization
      expect(fs_implied).to be_eql(first_specification)

      expect(first_specification.shortname).to be_eql('png-2')
      expect(first_specification.editor_draft).to be_eql('https://w3c.github.io/png/')
      expect(first_specification.description).to include('This document describes PNG (Portable Network Graphics)')
      expect(first_specification.title).to be_eql('Portable Network Graphics (PNG) Specification (Second Edition)')
      expect(first_specification.links.self.href).to be_eql('https://api.w3.org/specifications/png-2')
      # Verify only one request was made
      stubs.verify_stubbed_calls
    end

    it 'retrieves a specific specification by id' do
      model = register.fetch(:spec_resource, id: 'png-2')
      expect(model).to be_a(IntegrationSpec::Specification)
      expect(model.shortname).to eq('png-2')
    end

    context 'handles different HTTP status codes' do
      let!(:error_stubs) do
        {
          bad_request: stubs.get('/bad-request') do
            [400, { 'Content-Type' => 'application/json' }, { error: 'Bad Request' }.to_json]
          end,
          unauthorized: stubs.get('/unauthorized') do
            [401, { 'Content-Type' => 'application/json' }, { error: 'Unauthorized' }.to_json]
          end,
          not_found: stubs.get('/not-found') do
            [404, { 'Content-Type' => 'application/json' }, { error: 'Not Found' }.to_json]
          end,
          server_error: stubs.get('/server-error') do
            [500, { 'Content-Type' => 'application/json' }, { error: 'Internal Server Error' }.to_json]
          end
        }
      end

      it 'handles 400 Bad Request' do
        expect { client.get('/bad-request') }
          .to raise_error(Lutaml::Hal::BadRequestError)
      end

      it 'handles 401 Unauthorized' do
        expect { client.get('/unauthorized') }
          .to raise_error(Lutaml::Hal::UnauthorizedError)
      end

      it 'handles 404 Not Found' do
        expect { client.get('/not-found') }
          .to raise_error(Lutaml::Hal::NotFoundError)
      end

      it 'handles 500 Server Error' do
        expect { client.get('/server-error') }
          .to raise_error(Lutaml::Hal::ServerError)
      end
    end

    it 'handles errors gracefully' do
      expect { client.get_by_url('/invalid-url') }.to raise_error(Lutaml::Hal::LinkResolutionError)
    end

    it 'parses JSON responses correctly' do
      shortname = 'png-2'
      response = client.get("/specifications/#{shortname}")

      model = IntegrationSpec::Specification.from_json(response.to_json)

      expect(model).to be_a(Lutaml::Hal::Resource)
      expect(model.shortname).to eq('png-2')
      expect(model.title).to eq('Portable Network Graphics (PNG) Specification (Second Edition)')

      expect(model.links).to be_a(Lutaml::Model::Serializable)
      expect(model.links.self).to be_a(Lutaml::Hal::Link)
      expect(model.links.self.href).to be_eql('https://api.w3.org/specifications/png-2')
    end
  end
end
