# frozen_string_literal: true

require "test_helper"

class TestConnectionOptions < Minitest::Test
  include Helper::Client
  include Lint::ConnectionOptions
end
