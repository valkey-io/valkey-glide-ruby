# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in valkey.gemspec
gemspec

# irb dropped out of Ruby's default gems in 4.0; older rubies (down to the
# gemspec's minimum of 3.0) already ship it and must not have a version pinned.
gem "irb" if RUBY_VERSION >= "4.0"

gem "rake", "~> 13.0"

gem "rubocop", "~> 1.21"

group :test do
  gem "minitest", "~> 5.16"
  gem "minitest-reporters", "~> 1.4"
  gem "simplecov", "~> 1.1"
end
