# frozen_string_literal: true

require "test_helper"

class TestJsonCommands < Minitest::Test
  include Helper::Client
  include Lint::JsonCommands
end
