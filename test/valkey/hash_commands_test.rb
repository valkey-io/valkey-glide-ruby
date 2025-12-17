# frozen_string_literal: true

require "test_helper"

class TestHashCommands < Minitest::Test
  include Helper::Client
  include Lint::HashCommands
end
