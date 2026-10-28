# frozen_string_literal: true

require "minitest/autorun"
require "valkey/errors"
require "valkey/request_type"
require "valkey/utils"
require "valkey/commands/set_commands"

# Unit tests for set command request construction.
class TestSetCommandsUnit < Minitest::Test
  # Minimal command receiver that records dispatched requests.
  class FakeClient
    include Valkey::Commands::SetCommands

    attr_reader :captured_command, :captured_arguments

    def initialize(reply: nil, error: nil)
      @reply = reply
      @error = error
    end

    def send_command(request_type, command_arguments = [], &block)
      @captured_command = request_type
      @captured_arguments = command_arguments
      raise @error if @error

      block ? block.call(@reply) : @reply
    end
  end

  def test_sismember_if_exists
    member_exists_status = 1

    assert_sismember_if_exists(key: "my_set", member: "member1", reply: member_exists_status)
  end

  def test_sismember_if_exists_member_not_found
    member_not_found_status = 0

    assert_sismember_if_exists(key: "my_set", member: "member1", reply: member_not_found_status)
  end

  def test_sismember_if_exists_key_not_found
    key_not_found_status = -1

    assert_sismember_if_exists(key: "my_set", member: "member1", reply: key_not_found_status)
  end

  def test_sismember_if_exists_propagates_client_error
    error = Valkey::CommandError.new("error")
    client = FakeClient.new(error: error)

    raised_error = assert_raises(Valkey::CommandError) do
      client.sismember_if_exists("my_set", "member1")
    end

    assert_same error, raised_error
  end

  private

  def assert_sismember_if_exists(key:, member:, reply:)
    client = FakeClient.new(reply: reply)

    assert_equal reply, client.sismember_if_exists(key, member)
    assert_equal Valkey::RequestType::SISMEMBER, client.captured_command
    assert_equal [key, member, "XX"], client.captured_arguments

    client
  end
end
