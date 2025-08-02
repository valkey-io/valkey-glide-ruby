# frozen_string_literal: true

require "test_helper"

class TestSetCommands < Minitest::Test
  include Helper::Client
  include Lint::SetCommands
end
