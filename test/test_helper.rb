# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "valkey"

require "minitest/autorun"
require 'minitest/reporters'

require_relative 'support/helper/generic'
require_relative 'support/helper/version'
require_relative 'support/helper/client'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

$VERBOSE = true

PORT        = 6379
DB          = 15
TIMEOUT     = Float(ENV["TIMEOUT"] || 1.0)
LOW_TIMEOUT = Float(ENV["LOW_TIMEOUT"] || 0.01) # for blocking-command tests
OPTIONS     = { port: PORT, db: DB, timeout: TIMEOUT }.freeze

Dir[File.expand_path("lint/**/*.rb", __dir__)].sort.each do |f|
  require f
end
