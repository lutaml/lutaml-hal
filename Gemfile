# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in lutaml-hal.gemspec
gemspec

gem 'rake'
gem 'rspec'
gem 'rubocop'
gem 'rubocop-performance'
gem 'rubocop-rake'
gem 'rubocop-rspec'

# lutaml-store is not yet released. Use a sibling checkout for local
# co-development when present, otherwise fetch the branch (e.g. on CI).
if File.directory?(File.expand_path('../lutaml-store', __dir__))
  gem 'lutaml-store', path: '../lutaml-store'
else
  gem 'lutaml-store', git: 'https://github.com/lutaml/lutaml-store.git', branch: 'rt-tmp'
end
