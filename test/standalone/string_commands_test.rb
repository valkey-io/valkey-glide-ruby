# frozen_string_literal: true

require "test_helper"

class TestStringCommands < Minitest::Test
  include Helper::Client
  include Lint::StringCommands
end
