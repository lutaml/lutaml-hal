# frozen_string_literal: true

require 'lutaml/model'
require 'lutaml/store'

module Lutaml
  module Hal
    REGISTER_ID_ATTR_NAME = '_global_register_id'

    def self.debug_log(message)
      puts "[Lutaml::Hal] DEBUG: #{message}" if ENV['DEBUG_API']
    end

    autoload :VERSION, 'lutaml/hal/version'
    autoload :Error, 'lutaml/hal/errors'
    autoload :NotFoundError, 'lutaml/hal/errors'
    autoload :UnauthorizedError, 'lutaml/hal/errors'
    autoload :BadRequestError, 'lutaml/hal/errors'
    autoload :ServerError, 'lutaml/hal/errors'
    autoload :LinkResolutionError, 'lutaml/hal/errors'
    autoload :ParsingError, 'lutaml/hal/errors'
    autoload :ConnectionError, 'lutaml/hal/errors'
    autoload :TimeoutError, 'lutaml/hal/errors'
    autoload :TooManyRequestsError, 'lutaml/hal/errors'
    autoload :Cache, 'lutaml/hal/cache'
    autoload :Client, 'lutaml/hal/client'
    autoload :EndpointConfiguration, 'lutaml/hal/endpoint_configuration'
    autoload :EndpointParameter, 'lutaml/hal/endpoint_parameter'
    autoload :GlobalRegister, 'lutaml/hal/global_register'
    autoload :Link, 'lutaml/hal/link'
    autoload :LinkClassFactory, 'lutaml/hal/link_class_factory'
    autoload :LinkSet, 'lutaml/hal/link_set'
    autoload :LinkSetClassFactory, 'lutaml/hal/link_set_class_factory'
    autoload :ModelRegister, 'lutaml/hal/model_register'
    autoload :Page, 'lutaml/hal/page'
    autoload :RateLimiter, 'lutaml/hal/rate_limiter'
    autoload :Resource, 'lutaml/hal/resource'
    autoload :SingleFlight, 'lutaml/hal/single_flight'
    autoload :TypeResolver, 'lutaml/hal/type_resolver'
  end
end
