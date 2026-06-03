# frozen_string_literal: true

require "test_helper"

class TestConnectionCommands < Minitest::Test
  include Helper::Client
  include Lint::ConnectionCommands
end
