# frozen_string_literal: true

require_relative 'lib/lutaml/hal/version'

Gem::Specification.new do |spec|
  spec.name = 'lutaml-hal'
  spec.version = Lutaml::Hal::VERSION
  spec.authors = ['Ribose Inc.']
  spec.email = ['open.source@ribose.com']

  spec.summary = 'HAL implementation for LutaML'
  spec.description = 'Hypertext Application Language (HAL) implementation for Lutaml model'
  spec.homepage = 'https://github.com/lutaml/lutaml-hal'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.6.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.glob('lib/**/*') + %w[Gemfile LICENSE.md README.adoc]
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'faraday', '~> 2.0'
  spec.add_dependency 'faraday-follow_redirects', '~> 0.3'
  spec.add_dependency 'lutaml-model'
  spec.add_dependency 'rainbow', '~> 3.0'
end
