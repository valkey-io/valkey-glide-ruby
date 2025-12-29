# frozen_string_literal: true

require "test_helper"

class TestTransactionCommands < Minitest::Test
  include Helper::Client
  include Lint::TransactionCommands
end
