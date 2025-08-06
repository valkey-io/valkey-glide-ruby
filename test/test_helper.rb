# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "valkey"

require "minitest/autorun"
require 'minitest/reporters'

require_relative 'support/helper/generic'
require_relative 'support/helper/version'
require_relative 'support/helper/client'
require_relative 'support/helper/cluster'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

$VERBOSE = true

PORT        = 6379
DB          = 15
TIMEOUT = Float(ENV["TIMEOUT"] || 5.0) # Increased from 3.0 to 5.0 for CI stability
LOW_TIMEOUT = Float(ENV["LOW_TIMEOUT"] || 0.01) # for blocking-command tests

CLUSTER_NODES = 6.times.map do |i|
  { host: "127.0.0.1", port: 7000 + i }
end

Dir[File.expand_path("lint/**/*.rb", __dir__)].sort.each do |f|
  require f
end
