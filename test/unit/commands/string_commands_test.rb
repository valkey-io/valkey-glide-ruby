# frozen_string_literal: true

require "minitest/autorun"
require "valkey/errors"
require "valkey/request_type"
require "valkey/commands/string_commands"

# Unit tests for string command request construction.
class TestStringCommandsUnit < Minitest::Test
  # Minimal command receiver that records dispatched requests.
  class FakeClient
    include Valkey::Commands::StringCommands

    attr_reader :captured_command, :captured_arguments

    def initialize(reply: nil, error: nil)
      @reply = reply
      @error = error
    end

    def send_command(request_type, command_arguments = [])
      @captured_command = request_type
      @captured_arguments = command_arguments
      raise @error if @error

      @reply
    end
  end

  def test_delifeq
    assert_delifeq(key: "key", value: "value", expected_value: "value")
  end

  def test_delifeq_binary_value
    value = "\x00\xFF".b
    client = assert_delifeq(key: "key", value: value, expected_value: value)

    captured_value = client.captured_arguments.last
    # byte 0 = \x00, 255 = \xFF
    assert_equal [0, 255], captured_value.bytes
    assert_equal Encoding::BINARY, captured_value.encoding
  end

  def test_delifeq_non_string_value
    assert_delifeq(key: "key", value: %w[a b], expected_value: "[\"a\", \"b\"]")
  end

  def test_delifeq_stringifies_nil_value
    assert_delifeq(key: "key", value: nil, expected_value: "")
  end

  def test_delifeq_propagates_client_error
    error = Valkey::CommandError.new("boom")
    client = FakeClient.new(error: error)

    raised_error = assert_raises(Valkey::CommandError) { client.delifeq("key", "value") }

    assert_same error, raised_error
  end

  private

  def assert_delifeq(key:, value:, expected_value:)
    client = FakeClient.new(reply: 0)

    assert_equal 0, client.delifeq(key, value)
    assert_equal Valkey::RequestType::DEL_IF_EQ, client.captured_command
    assert_equal [key, expected_value], client.captured_arguments

    client
  end
end
