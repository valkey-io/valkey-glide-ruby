# frozen_string_literal: true

require "test_helper"

class TestBitmapCommands < Minitest::Test
  include Helper::Client
  include Lint::BitmapCommands
end
