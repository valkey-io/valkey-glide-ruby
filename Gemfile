# frozen_string_literal: true

source "https://rubygems.org"

# When TEST_INSTALLED_GEM is set, we test against the installed gem
# instead of the local source. This is used in CD to verify the built gem works.
unless ENV["TEST_INSTALLED_GEM"]
  # Specify your gem's dependencies in valkey.gemspec
  gemspec
end

gem "rake", "~> 13.0"

gem "minitest", "~> 5.16"

gem "minitest-reporters", "~> 1.4"

gem "rubocop", "~> 1.21"
