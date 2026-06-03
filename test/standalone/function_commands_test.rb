# frozen_string_literal: true

require "test_helper"

class TestFunctionCommands < Minitest::Test
  include Helper::Client
  include Lint::FunctionCommands

  def setup
    super
    # Ensure the function registry is empty before running tests
    r.function_flush
  rescue StandardError
    nil
  end

  def teardown
    # Clean up after tests
    r.function_flush
  rescue StandardError
    nil
  ensure
    super
  end
end
