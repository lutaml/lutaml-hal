# frozen_string_literal: true

module Lutaml
  module Hal
    module Cache
      autoload :CacheConfiguration, 'lutaml/hal/cache/cache_configuration'
      autoload :CacheEntry, 'lutaml/hal/cache/cache_entry'
      autoload :CacheManager, 'lutaml/hal/cache/cache_manager'
      autoload :CacheMetadata, 'lutaml/hal/cache/cache_metadata'
      autoload :ResponseAdapter, 'lutaml/hal/cache/response_adapter'
    end
  end
end
