# frozen_string_literal: true

require "test_helper"

class TestIamAuthentication < Minitest::Test
  def build_client(connection: FFI::Pointer.new(1))
    client = Valkey.allocate
    client.instance_variable_set(:@connection, connection)
    client.instance_variable_set(:@pid, Process.pid)
    client
  end

  def successful_result
    response = Valkey::Bindings::CommandResponse.new
    response[:response_type] = Valkey::ResponseType::OK

    result = Valkey::Bindings::CommandResult.new
    result[:response] = response

    @ffi_fixture = [result, response]
    result
  end

  def failed_result(message)
    message_buffer = FFI::MemoryPointer.from_string(message)
    command_error = Valkey::Bindings::CommandError.new
    command_error.to_ptr.put_pointer(
      Valkey::Bindings::CommandError.offset_of(:command_error_message),
      message_buffer
    )
    command_error[:command_error_type] = Valkey::RequestErrorType::UNSPECIFIED

    result = Valkey::Bindings::CommandResult.new
    result[:command_error] = command_error

    @ffi_fixture = [result, command_error, message_buffer]
    result
  end

  def test_refresh_iam_token_calls_ffi_and_returns_ok
    connection = FFI::Pointer.new(1)
    client = build_client(connection: connection)
    result = successful_result
    ffi_calls = []
    free_calls = []

    Valkey::Bindings.stub(:refresh_iam_token, lambda { |connection_handle, request_id|
      ffi_calls << [connection_handle, request_id]
      result.to_ptr
    }) do
      Valkey::Bindings.stub(:free_command_result, ->(result_pointer) { free_calls << result_pointer }) do
        assert_equal "OK", client.refresh_iam_token
      end
    end

    assert_equal [[connection, 0]], ffi_calls
    assert_equal 1, free_calls.size
    assert_equal result.to_ptr.address, free_calls.first.address
  end

  def test_refresh_iam_token_frees_failed_result
    client = build_client
    result = failed_result("refresh failed")
    ffi_calls = []
    free_calls = []

    error = Valkey::Bindings.stub(:refresh_iam_token, lambda { |connection_handle, request_id|
      ffi_calls << [connection_handle, request_id]
      result.to_ptr
    }) do
      Valkey::Bindings.stub(:free_command_result, ->(result_pointer) { free_calls << result_pointer }) do
        assert_raises(Valkey::CommandError) { client.refresh_iam_token }
      end
    end

    assert_equal "refresh failed", error.message
    assert_equal 1, ffi_calls.size
    assert_equal 1, free_calls.size
    assert_equal result.to_ptr.address, free_calls.first.address
  end

  def test_refresh_iam_token_rejects_closed_client
    client = build_client(connection: nil)
    ffi_calls = []
    free_calls = []

    Valkey::Bindings.stub(:refresh_iam_token, ->(*args) { ffi_calls << args }) do
      Valkey::Bindings.stub(:free_command_result, ->(result_pointer) { free_calls << result_pointer }) do
        assert_raises(Valkey::ConnectionError) { client.refresh_iam_token }
      end
    end

    assert_empty ffi_calls
    assert_empty free_calls
  end
end
