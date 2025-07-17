# frozen_string_literal: true

require "test_helper"

class SortedSetCommandsTest < Minitest::Test
  include Helper::Client
  include Lint::SortedSetCommands
end
