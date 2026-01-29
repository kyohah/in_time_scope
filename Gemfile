# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in in_time_scope.gemspec
gemspec

# Allow testing with different Rails versions via RAILS_VERSION env var
rails_version = ENV.fetch("RAILS_VERSION", nil)

gem "activerecord", "~> #{rails_version}.0" if rails_version
