# frozen_string_literal: true

require "test_helper"

# Unit tests for Valkey#convert_response's error-type dispatch. These build a
# fake FFI CommandResult directly (no running server) so both branches -
# EXECABORT and UNSPECIFIED - can be exercised, including the EXECABORT one
# that a real queue-time abort is otherwise very hard to reach through this
# client's current architecture (see #260/#264 investigation).
class TestErrorsUnit < Minitest::Test
  def test_execabort_raises_exec_abort_error
    client = Valkey.allocate

    error = assert_raises(Valkey::ExecAbortError) do
      client.send(:convert_response, fake_command_result(Valkey::RequestErrorType::EXECABORT, "aborted"))
    end
    assert_equal "aborted", error.message
  end

  def test_unspecified_raises_plain_command_error_not_exec_abort_error
    client = Valkey.allocate

    error = assert_raises(Valkey::CommandError) do
      client.send(:convert_response, fake_command_result(Valkey::RequestErrorType::UNSPECIFIED, "boom"))
    end
    refute_kind_of Valkey::ExecAbortError, error
  end

  private

  def fake_command_result(error_type, message)
    msg_buf = FFI::MemoryPointer.from_string(message)
    command_error = Valkey::Bindings::CommandError.new
    command_error.to_ptr.put_pointer(command_error.offset_of(:command_error_message), msg_buf)
    command_error[:command_error_type] = error_type

    result = Valkey::Bindings::CommandResult.new
    result[:command_error] = command_error
    result.to_ptr
  end
end
