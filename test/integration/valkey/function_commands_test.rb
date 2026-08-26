# frozen_string_literal: true

module ValkeyTests
  module FunctionCommands
    def setup
      super if defined?(super)
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
      super if defined?(super)
    end
  end
end
