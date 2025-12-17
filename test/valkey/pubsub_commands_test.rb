# frozen_string_literal: true

require_relative "../test_helper"

class TestPubSubCommands < Minitest::Test
  include Helper::Client
  include Lint::PubSubCommands
end
