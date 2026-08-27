# frozen_string_literal: true

require "test_helper"

# Unit tests for Valkey's error class hierarchy. These do not require a
# running server.
class TestErrorsUnit < Minitest::Test
  def test_exec_abort_error_is_a_command_error
    assert Valkey::ExecAbortError < Valkey::CommandError
  end

  def test_exec_abort_error_is_distinct_from_plain_command_error
    refute_equal Valkey::ExecAbortError, Valkey::CommandError
    assert_kind_of Valkey::CommandError, Valkey::ExecAbortError.new("boom")
  end
end
