# frozen_string_literal: true

require "test_helper"

class TestHyperLogLogCommands < Minitest::Test
  include Helper::Client
  include Lint::HyperLogLog
end
