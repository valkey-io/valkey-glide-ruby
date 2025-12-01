# frozen_string_literal: true

require "test_helper"

class TestVectorSearchCommands < Minitest::Test
  include Helper::Client
  include Lint::VectorSearchCommands
end
