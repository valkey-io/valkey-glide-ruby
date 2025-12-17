# frozen_string_literal: true

require "test_helper"

class TestStreamCommands < Minitest::Test
  include Helper::Client
  include Lint::StreamCommands
end
