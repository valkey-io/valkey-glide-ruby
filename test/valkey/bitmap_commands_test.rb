# frozen_string_literal: true

require "test_helper"

class TestBitpos < Minitest::Test
  include Helper::Client
  include Lint::BitmapCommands
end
