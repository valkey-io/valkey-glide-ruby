# frozen_string_literal: true

require "test_helper"

class TestCommandsOnString < Minitest::Test
  include Helper::Client
  include Lint::GeoCommands
end
