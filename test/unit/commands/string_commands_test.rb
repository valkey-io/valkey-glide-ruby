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

    attr_reader :captured_type, :captured_arguments

    def initialize(canned_reply: nil, canned_error: nil)
      @canned_reply = canned_reply
      @canned_error = canned_error
    end

    def send_command(request_type, command_arguments = [])
      @captured_type = request_type
      @captured_arguments = command_arguments
      raise @canned_error if @canned_error

      @canned_reply
    end
  end

  def test_delifeq
    client = FakeClient.new(canned_reply: 0)

    assert_equal 0, client.delifeq("key", "value")
    assert_equal Valkey::RequestType::DEL_IF_EQ, client.captured_type
    assert_equal %w[key value], client.captured_arguments
  end

  def test_delifeq_stringifies_non_string_value
    client = FakeClient.new
    value = %w[a b]

    client.delifeq("key", value)

    assert_equal ["key", value.to_s], client.captured_arguments
  end

  def test_delifeq_stringifies_nil_value
    client = FakeClient.new

    client.delifeq("key", nil)

    assert_equal ["key", ""], client.captured_arguments
  end

  def test_delifeq_propagates_client_error
    error = Valkey::CommandError.new("boom")
    client = FakeClient.new(canned_error: error)

    raised_error = assert_raises(Valkey::CommandError) { client.delifeq("key", "value") }

    assert_same error, raised_error
  end
end
