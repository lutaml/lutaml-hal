#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo showing Lutaml::Hal cache integration with Lutaml::Store
# This example demonstrates how to use caching with HAL resources

require 'lutaml/hal'
require 'lutaml/store'

# Example HAL resource models
class User < Lutaml::Hal::Resource
  attribute :id, :integer
  attribute :name, :string
  attribute :email, :string

  link :self, '/users/{id}'
  link :posts, '/users/{id}/posts'
end

class Post < Lutaml::Hal::Resource
  attribute :id, :integer
  attribute :title, :string
  attribute :content, :string
  attribute :author_id, :integer

  link :self, '/posts/{id}'
  link :author, '/users/{author_id}'
end

# Mock HTTP client for demonstration
class MockClient
  attr_accessor :api_url

  def initialize(api_url)
    @api_url = api_url
    @request_count = 0
  end

  def get(path)
    @request_count += 1
    puts "HTTP GET #{@api_url}#{path} (Request ##{@request_count})"

    case path
    when '/users/1'
      {
        'id' => 1,
        'name' => 'John Doe',
        'email' => 'john@example.com',
        '_links' => {
          'self' => { 'href' => '/users/1' },
          'posts' => { 'href' => '/users/1/posts' }
        }
      }
    when '/users/1/posts'
      {
        '_embedded' => {
          'posts' => [
            {
              'id' => 1,
              'title' => 'First Post',
              'content' => 'Hello World',
              'author_id' => 1,
              '_links' => {
                'self' => { 'href' => '/posts/1' },
                'author' => { 'href' => '/users/1' }
              }
            }
          ]
        },
        '_links' => {
          'self' => { 'href' => '/users/1/posts' }
        }
      }
    when '/posts/1'
      {
        'id' => 1,
        'title' => 'First Post',
        'content' => 'Hello World',
        'author_id' => 1,
        '_links' => {
          'self' => { 'href' => '/posts/1' },
          'author' => { 'href' => '/users/1' }
        }
      }
    else
      raise "Unknown path: #{path}"
    end
  end

  def get_by_url(url)
    path = url.sub(@api_url, '')
    get(path)
  end

  def get_with_headers(url, headers)
    puts "Headers: #{headers}"
    get(url)
  end

  def request_count
    @request_count
  end
end

def demo_cache_integration
  puts "=== Lutaml::Hal Cache Integration Demo ==="
  puts

  # Create mock client
  client = MockClient.new('https://api.example.com')

  # Configure cache with different adapters
  cache_configs = {
    memory: { type: :memory, max_size: 100 },
    filesystem: {
      type: :filesystem,
      path: '/tmp/hal_cache',
      max_size: 1000
    }
  }

  cache_configs.each do |cache_type, cache_config|
    puts "--- Testing with #{cache_type.upcase} cache ---"

    # Create model register with cache
    register = Lutaml::Hal::ModelRegister.new(
      name: "demo_#{cache_type}",
      client: client,
      cache: { adapter: cache_config, ttl: 300 }
    )

    # Register endpoints
    register.add_endpoint(
      id: :user,
      type: :show,
      url: '/users/{id}',
      model: User,
      parameters: [
        Lutaml::Hal::EndpointParameter.new(
          name: 'id',
          location: :path,
          required: true,
          type: :integer
        )
      ]
    )

    register.add_endpoint(
      id: :user_posts,
      type: :index,
      url: '/users/{id}/posts',
      model: Post,
      parameters: [
        Lutaml::Hal::EndpointParameter.new(
          name: 'id',
          location: :path,
          required: true,
          type: :integer
        )
      ]
    )

    # Register with global register
    Lutaml::Hal::GlobalRegister.instance.register("demo_#{cache_type}", register)

    puts "Initial request count: #{client.request_count}"

    # First fetch - should hit the API
    puts "\n1. First fetch (cache miss):"
    user1 = register.fetch(:user, id: 1)
    puts "User: #{user1.name} (#{user1.email})"
    puts "Request count after first fetch: #{client.request_count}"

    # Second fetch - should hit cache
    puts "\n2. Second fetch (cache hit):"
    user2 = register.fetch(:user, id: 1)
    puts "User: #{user2.name} (#{user2.email})"
    puts "Request count after second fetch: #{client.request_count}"

    # Cache info
    puts "\n3. Cache information:"
    cache_info = register.cache_info
    puts "Cache adapter: #{cache_info[:adapter_type]}"
    puts "Cache size: #{cache_info[:current_size]}/#{cache_info[:max_size]}"
    puts "Cache stats: #{cache_info[:stats]}"

    # Test link resolution with cache
    puts "\n4. Link resolution with cache:"
    posts_link = user1.posts
    posts1 = posts_link.realize
    puts "Posts count: #{posts1._embedded['posts'].length}"
    puts "Request count after posts fetch: #{client.request_count}"

    # Second link resolution - should hit cache
    posts2 = posts_link.realize
    puts "Posts count (cached): #{posts2._embedded['posts'].length}"
    puts "Request count after cached posts fetch: #{client.request_count}"

    # Force refresh
    puts "\n5. Force refresh (bypass cache):"
    posts3 = posts_link.realize(force_refresh: true)
    puts "Posts count (force refresh): #{posts3._embedded['posts'].length}"
    puts "Request count after force refresh: #{client.request_count}"

    # Clear cache
    puts "\n6. Clear cache:"
    register.clear_cache
    user3 = register.fetch(:user, id: 1)
    puts "User after cache clear: #{user3.name}"
    puts "Request count after cache clear: #{client.request_count}"

    puts "\nFinal cache stats: #{register.cache_stats}"
    puts
  end

  # Global cache management
  puts "--- Global Cache Management ---"
  global_stats = Lutaml::Hal::GlobalRegister.instance.cache_stats
  puts "All register cache stats:"
  global_stats.each do |name, stats|
    puts "  #{name}: #{stats}"
  end

  puts "\nClearing all caches..."
  Lutaml::Hal::GlobalRegister.instance.clear_all_caches
  puts "All caches cleared."
end

def demo_cache_configuration_options
  puts "\n=== Cache Configuration Options ==="

  # Different cache configurations
  configs = [
    {
      name: "Memory with TTL",
      config: {
        adapter: { type: :memory },
        ttl: 60,
        max_size: 50
      }
    },
    {
      name: "Filesystem with compression",
      config: {
        adapter: {
          type: :filesystem,
          path: '/tmp/hal_cache_compressed',
          compression: { algorithm: :gzip, level: 6 }
        },
        ttl: 3600,
        max_size: 1000
      }
    },
    {
      name: "SQLite with encryption",
      config: {
        adapter: {
          type: :sqlite,
          path: '/tmp/hal_cache.db',
          encryption: { key: 'demo-key-32-chars-long-exactly!' }
        },
        ttl: 1800,
        max_size: 5000
      }
    }
  ]

  configs.each do |config_info|
    puts "\n--- #{config_info[:name]} ---"

    begin
      register = Lutaml::Hal::ModelRegister.new(
        name: config_info[:name].downcase.gsub(/\s+/, '_'),
        cache: config_info[:config]
      )

      cache_info = register.cache_info
      puts "✓ Configuration successful"
      puts "  Adapter: #{cache_info[:adapter_type]}"
      puts "  TTL: #{cache_info[:default_ttl]}s"
      puts "  Max size: #{cache_info[:max_size]}"

    rescue => e
      puts "✗ Configuration failed: #{e.message}"
    end
  end
end

def demo_cache_performance
  puts "\n=== Cache Performance Demo ==="

  client = MockClient.new('https://api.example.com')

  # Create register without cache
  register_no_cache = Lutaml::Hal::ModelRegister.new(
    name: 'no_cache',
    client: client
  )

  # Create register with cache
  register_with_cache = Lutaml::Hal::ModelRegister.new(
    name: 'with_cache',
    client: client,
    cache: { adapter: { type: :memory }, ttl: 300 }
  )

  # Register endpoints for both
  [register_no_cache, register_with_cache].each do |register|
    register.add_endpoint(
      id: :user,
      type: :show,
      url: '/users/{id}',
      model: User,
      parameters: [
        Lutaml::Hal::EndpointParameter.new(
          name: 'id',
          location: :path,
          required: true,
          type: :integer
        )
      ]
    )
  end

  # Performance test
  iterations = 10

  puts "Fetching user #{iterations} times..."

  # Without cache
  start_time = Time.now
  start_requests = client.request_count
  iterations.times { register_no_cache.fetch(:user, id: 1) }
  no_cache_time = Time.now - start_time
  no_cache_requests = client.request_count - start_requests

  # Reset client counter
  client.instance_variable_set(:@request_count, 0)

  # With cache
  start_time = Time.now
  start_requests = client.request_count
  iterations.times { register_with_cache.fetch(:user, id: 1) }
  cache_time = Time.now - start_time
  cache_requests = client.request_count - start_requests

  puts "\nResults:"
  puts "Without cache: #{no_cache_time.round(4)}s, #{no_cache_requests} HTTP requests"
  puts "With cache:    #{cache_time.round(4)}s, #{cache_requests} HTTP requests"
  puts "Speedup:       #{(no_cache_time / cache_time).round(2)}x"
  puts "Request reduction: #{((no_cache_requests - cache_requests).to_f / no_cache_requests * 100).round(1)}%"
end

if __FILE__ == $0
  demo_cache_integration
  demo_cache_configuration_options
  demo_cache_performance

  puts "\n=== Demo Complete ==="
  puts "This demo showed:"
  puts "• Cache integration with different adapters (memory, filesystem, SQLite)"
  puts "• Cache configuration options (TTL, compression, encryption)"
  puts "• Performance benefits of caching"
  puts "• Global cache management"
  puts "• Force refresh capabilities"
  puts "• Cache statistics and monitoring"
end
