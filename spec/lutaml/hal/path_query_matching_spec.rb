# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Path and Query Parameter Matching' do
  let(:register) { Lutaml::Hal::ModelRegister.new(name: :test_register) }
  let(:client) { instance_double(Lutaml::Hal::Client, api_url: 'https://api.example.com') }

  before do
    allow(register).to receive(:client).and_return(client)
  end

  describe 'URL pattern matching' do
    context 'simple path patterns' do
      it 'matches exact paths' do
        register.add_endpoint(
          id: :users,
          type: :get,
          url: '/users',
          model: 'UserCollection'
        )

        result = register.send(:find_matching_model_class, '/users')
        expect(result).not_to be_nil
        expect(result).to eq('UserCollection')
      end

      it 'does not match different paths' do
        register.add_endpoint(
          id: :users,
          type: :get,
          url: '/users',
          model: 'UserCollection'
        )

        result = register.send(:find_matching_model_class, '/groups')
        expect(result).to be_nil
      end
    end

    context 'templated path patterns' do
      it 'matches single parameter templates' do
        register.add_endpoint(
          id: :user,
          type: :get,
          url: '/users/{id}',
          model: 'User',
          parameters: [
            Lutaml::Hal::EndpointParameter.path('id',
                                                schema: { type: :string },
                                                description: 'User identifier')
          ]
        )

        result = register.send(:find_matching_model_class, '/users/123')
        expect(result).not_to be_nil
        expect(result).to eq('User')
      end

      it 'matches multiple parameter templates' do
        register.add_endpoint(
          id: :user_post,
          type: :get,
          url: '/users/{user_id}/posts/{post_id}',
          model: 'Post',
          parameters: [
            Lutaml::Hal::EndpointParameter.path('user_id',
                                                schema: { type: :string },
                                                description: 'User identifier'),
            Lutaml::Hal::EndpointParameter.path('post_id',
                                                schema: { type: :string },
                                                description: 'Post identifier')
          ]
        )

        result = register.send(:find_matching_model_class, '/users/123/posts/456')
        expect(result).not_to be_nil
        expect(result).to eq('Post')
      end

      it 'does not match across path segments' do
        register.add_endpoint(
          id: :user,
          type: :get,
          url: '/users/{id}',
          model: 'User',
          parameters: [
            Lutaml::Hal::EndpointParameter.path('id',
                                                schema: { type: :string },
                                                description: 'User identifier')
          ]
        )

        # Should not match because {id} should only match a single segment
        result = register.send(:find_matching_model_class, '/users/123/extra')
        expect(result).to be_nil
      end

      it 'matches nested resource patterns' do
        register.add_endpoint(
          id: :user_posts,
          type: :get,
          url: '/users/{user_id}/posts',
          model: 'PostCollection',
          parameters: [
            Lutaml::Hal::EndpointParameter.path('user_id',
                                                schema: { type: :string },
                                                description: 'User identifier')
          ]
        )

        result = register.send(:find_matching_model_class, '/users/123/posts')
        expect(result).not_to be_nil
        expect(result).to eq('PostCollection')
      end
    end

    context 'pattern specificity' do
      it 'selects the most specific pattern when multiple match' do
        # Add less specific pattern first
        register.add_endpoint(
          id: :users,
          type: :get,
          url: '/users',
          model: 'UserCollection'
        )

        # Add more specific pattern
        register.add_endpoint(
          id: :admin_users,
          type: :get,
          url: '/users/admin',
          model: 'AdminUserCollection'
        )

        # Should match the more specific pattern
        result = register.send(:find_matching_model_class, '/users/admin')
        expect(result).not_to be_nil
        expect(result).to eq('AdminUserCollection')
      end

      it 'falls back to less specific pattern when more specific does not match' do
        register.add_endpoint(
          id: :users,
          type: :get,
          url: '/users',
          model: 'UserCollection'
        )

        register.add_endpoint(
          id: :admin_users,
          type: :get,
          url: '/users/admin',
          model: 'AdminUserCollection'
        )

        # Should match the less specific pattern
        result = register.send(:find_matching_model_class, '/users')
        expect(result).not_to be_nil
        expect(result).to eq('UserCollection')
      end
    end
  end

  describe 'query parameter matching' do
    context 'template query parameters' do
      it 'matches URLs with template query parameters' do
        register.add_endpoint(
          id: :users_paginated,
          type: :get,
          url: '/users',
          model: 'UserCollection',
          parameters: [
            Lutaml::Hal::EndpointParameter.query('page',
                                                 schema: { type: :integer },
                                                 description: 'Page number')
          ]
        )

        # Should match with page parameter
        result = register.send(:find_matching_model_class, '/users?page=2')
        expect(result).not_to be_nil
        expect(result).to eq('UserCollection')

        # Should also match without page parameter (template params are optional)
        result = register.send(:find_matching_model_class, '/users')
        expect(result).not_to be_nil
        expect(result).to eq('UserCollection')
      end

      it 'matches URLs with multiple template query parameters' do
        register.add_endpoint(
          id: :users_filtered,
          type: :get,
          url: '/users',
          model: 'UserCollection',
          parameters: [
            Lutaml::Hal::EndpointParameter.query('page',
                                                 schema: { type: :integer },
                                                 description: 'Page number'),
            Lutaml::Hal::EndpointParameter.query('limit',
                                                 schema: { type: :integer },
                                                 description: 'Items per page')
          ]
        )

        # Should match with both parameters
        result = register.send(:find_matching_model_class, '/users?page=2&limit=10')
        expect(result).not_to be_nil
        expect(result).to eq('UserCollection')

        # Should match with one parameter
        result = register.send(:find_matching_model_class, '/users?page=2')
        expect(result).not_to be_nil
        expect(result).to eq('UserCollection')

        # Should match with no parameters
        result = register.send(:find_matching_model_class, '/users')
        expect(result).not_to be_nil
        expect(result).to eq('UserCollection')
      end
    end

    context 'fixed query parameters' do
      it 'matches URLs with exact query parameter values' do
        register.add_endpoint(
          id: :active_users,
          type: :get,
          url: '/users',
          model: 'ActiveUserCollection',
          parameters: [
            Lutaml::Hal::EndpointParameter.query('status',
                                                 schema: { type: :string, enum: ['active'] },
                                                 description: 'User status filter',
                                                 required: true)
          ]
        )

        # Should match with exact parameter value
        result = register.send(:find_matching_model_class, '/users?status=active')
        expect(result).not_to be_nil
        expect(result).to eq('ActiveUserCollection')

        # Should not match with different parameter value
        result = register.send(:find_matching_model_class, '/users?status=inactive')
        expect(result).to be_nil

        # Should not match without the required parameter
        result = register.send(:find_matching_model_class, '/users')
        expect(result).to be_nil
      end

      it 'matches URLs with mixed template and fixed query parameters' do
        register.add_endpoint(
          id: :active_users_paginated,
          type: :get,
          url: '/users',
          model: 'ActiveUserCollection',
          parameters: [
            Lutaml::Hal::EndpointParameter.query('status',
                                                 schema: { type: :string, enum: ['active'] },
                                                 description: 'User status filter',
                                                 required: true),
            Lutaml::Hal::EndpointParameter.query('page',
                                                 schema: { type: :integer },
                                                 description: 'Page number')
          ]
        )

        # Should match with both parameters
        result = register.send(:find_matching_model_class, '/users?status=active&page=2')
        expect(result).not_to be_nil
        expect(result).to eq('ActiveUserCollection')

        # Should match with only the required fixed parameter
        result = register.send(:find_matching_model_class, '/users?status=active')
        expect(result).not_to be_nil
        expect(result).to eq('ActiveUserCollection')

        # Should not match without the required fixed parameter
        result = register.send(:find_matching_model_class, '/users?page=2')
        expect(result).to be_nil
      end
    end
  end

  describe 'combined path and query matching' do
    it 'matches templated paths with query parameters' do
      register.add_endpoint(
        id: :user_posts_paginated,
        type: :get,
        url: '/users/{user_id}/posts',
        model: 'PostCollection',
        parameters: [
          Lutaml::Hal::EndpointParameter.path('user_id',
                                              schema: { type: :string },
                                              description: 'User identifier'),
          Lutaml::Hal::EndpointParameter.query('page',
                                               schema: { type: :integer },
                                               description: 'Page number'),
          Lutaml::Hal::EndpointParameter.query('status',
                                               schema: { type: :string, enum: ['published'] },
                                               description: 'Post status filter',
                                               required: true)
        ]
      )

      # Should match with all parameters
      result = register.send(:find_matching_model_class, '/users/123/posts?page=2&status=published')
      expect(result).not_to be_nil
      expect(result).to eq('PostCollection')

      # Should match with only required parameters
      result = register.send(:find_matching_model_class, '/users/123/posts?status=published')
      expect(result).not_to be_nil
      expect(result).to eq('PostCollection')

      # Should not match without required query parameter
      result = register.send(:find_matching_model_class, '/users/123/posts?page=2')
      expect(result).to be_nil

      # Should not match with wrong path parameter count
      result = register.send(:find_matching_model_class, '/users/posts?status=published')
      expect(result).to be_nil
    end
  end

  describe 'URL building with interpolation' do
    it 'interpolates path parameters' do
      url_template = '/users/{user_id}/posts/{post_id}'
      params = { user_id: 123, post_id: 456 }

      result = register.send(:interpolate_url, url_template, params)
      expect(result).to eq('/users/123/posts/456')
    end

    it 'builds URLs with query parameters' do
      base_url = '/users'
      query_params_template = { 'page' => '{page}', 'limit' => '{limit}' }
      params = { page: 2, limit: 10 }

      result = register.send(:build_url_with_query_params, base_url, query_params_template, params)
      expect(result).to eq('/users?page=2&limit=10')
    end

    it 'builds URLs with partial query parameters' do
      base_url = '/users'
      query_params_template = { 'page' => '{page}', 'limit' => '{limit}' }
      params = { page: 2 } # missing limit

      result = register.send(:build_url_with_query_params, base_url, query_params_template, params)
      expect(result).to eq('/users?page=2')
    end

    it 'returns base URL when no query parameters match' do
      base_url = '/users'
      query_params_template = { 'page' => '{page}', 'limit' => '{limit}' }
      params = { other_param: 'value' } # no matching params

      result = register.send(:build_url_with_query_params, base_url, query_params_template, params)
      expect(result).to eq('/users')
    end
  end

  describe 'edge cases and error handling' do
    it 'handles URLs with special characters' do
      register.add_endpoint(
        id: :user,
        type: :get,
        url: '/users/{id}',
        model: 'User',
        parameters: [
          Lutaml::Hal::EndpointParameter.path('id',
                                              schema: { type: :string },
                                              description: 'User identifier')
        ]
      )

      # Should handle URL-encoded characters
      result = register.send(:find_matching_model_class, '/users/user%40example.com')
      expect(result).not_to be_nil
      expect(result).to eq('User')
    end

    it 'handles empty query strings' do
      register.add_endpoint(
        id: :users,
        type: :get,
        url: '/users',
        model: 'UserCollection',
        parameters: [
          Lutaml::Hal::EndpointParameter.query('page',
                                               schema: { type: :integer },
                                               description: 'Page number')
        ]
      )

      result = register.send(:find_matching_model_class, '/users?')
      expect(result).not_to be_nil
      expect(result).to eq('UserCollection')
    end

    it 'handles malformed query strings gracefully' do
      register.add_endpoint(
        id: :users,
        type: :get,
        url: '/users',
        model: 'UserCollection',
        parameters: [
          Lutaml::Hal::EndpointParameter.query('page',
                                               schema: { type: :integer },
                                               description: 'Page number')
        ]
      )

      # Should not crash on malformed query string
      expect do
        register.send(:find_matching_model_class, '/users?page=&invalid=')
      end.not_to raise_error
    end

    it 'prevents duplicate URL patterns' do
      register.add_endpoint(
        id: :users1,
        type: :get,
        url: '/users',
        model: 'UserCollection'
      )

      expect do
        register.add_endpoint(
          id: :users2,
          type: :get,
          url: '/users',
          model: 'UserCollection'
        )
      end.to raise_error(/Duplicate URL pattern/)
    end

    it 'allows same URL pattern with different query parameters' do
      register.add_endpoint(
        id: :users_all,
        type: :get,
        url: '/users',
        model: 'UserCollection'
      )

      expect do
        register.add_endpoint(
          id: :users_paginated,
          type: :get,
          url: '/users',
          model: 'UserCollection',
          parameters: [
            Lutaml::Hal::EndpointParameter.query('page',
                                                 schema: { type: :integer },
                                                 description: 'Page number')
          ]
        )
      end.not_to raise_error
    end
  end

  describe 'real-world scenarios' do
    before do
      # Set up a realistic API endpoint structure
      register.add_endpoint(
        id: :users_index,
        type: :get,
        url: '/users',
        model: 'UserCollection'
      )

      register.add_endpoint(
        id: :users_paginated,
        type: :get,
        url: '/users',
        model: 'UserCollection',
        parameters: [
          Lutaml::Hal::EndpointParameter.query('page',
                                               schema: { type: :integer },
                                               description: 'Page number'),
          Lutaml::Hal::EndpointParameter.query('per_page',
                                               schema: { type: :integer },
                                               description: 'Items per page')
        ]
      )

      register.add_endpoint(
        id: :user_show,
        type: :get,
        url: '/users/{id}',
        model: 'User',
        parameters: [
          Lutaml::Hal::EndpointParameter.path('id',
                                              schema: { type: :string },
                                              description: 'User identifier')
        ]
      )

      register.add_endpoint(
        id: :user_posts,
        type: :get,
        url: '/users/{user_id}/posts',
        model: 'PostCollection',
        parameters: [
          Lutaml::Hal::EndpointParameter.path('user_id',
                                              schema: { type: :string },
                                              description: 'User identifier')
        ]
      )

      register.add_endpoint(
        id: :user_posts_filtered,
        type: :get,
        url: '/users/{user_id}/posts',
        model: 'PostCollection',
        parameters: [
          Lutaml::Hal::EndpointParameter.path('user_id',
                                              schema: { type: :string },
                                              description: 'User identifier'),
          Lutaml::Hal::EndpointParameter.query('status',
                                               schema: { type: :string, enum: ['published'] },
                                               description: 'Post status filter',
                                               required: true),
          Lutaml::Hal::EndpointParameter.query('page',
                                               schema: { type: :integer },
                                               description: 'Page number')
        ]
      )

      register.add_endpoint(
        id: :post_show,
        type: :get,
        url: '/users/{user_id}/posts/{id}',
        model: 'Post',
        parameters: [
          Lutaml::Hal::EndpointParameter.path('user_id',
                                              schema: { type: :string },
                                              description: 'User identifier'),
          Lutaml::Hal::EndpointParameter.path('id',
                                              schema: { type: :string },
                                              description: 'Post identifier')
        ]
      )
    end

    it 'correctly routes various API calls' do
      # Basic collection
      result = register.send(:find_matching_model_class, '/users')
      expect(result).to eq('UserCollection')

      # Paginated collection (should prefer the more specific one with query params)
      result = register.send(:find_matching_model_class, '/users?page=2')
      expect(result).to eq('UserCollection')

      # Individual resource
      result = register.send(:find_matching_model_class, '/users/123')
      expect(result).to eq('User')

      # Nested collection
      result = register.send(:find_matching_model_class, '/users/123/posts')
      expect(result).to eq('PostCollection')

      # Filtered nested collection
      result = register.send(:find_matching_model_class, '/users/123/posts?status=published')
      expect(result).to eq('PostCollection')

      # Nested individual resource
      result = register.send(:find_matching_model_class, '/users/123/posts/456')
      expect(result).to eq('Post')
    end

    it 'handles URL building for complex scenarios' do
      # Build a paginated user posts URL
      url_template = '/users/{user_id}/posts'
      query_params_template = { 'status' => 'published', 'page' => '{page}' }
      params = { user_id: 123, page: 2 }

      interpolated_url = register.send(:interpolate_url, url_template, params)
      final_url = register.send(:build_url_with_query_params, interpolated_url, query_params_template, params)

      expect(final_url).to eq('/users/123/posts?status=published&page=2')
    end
  end
end
