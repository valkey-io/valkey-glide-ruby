# frozen_string_literal: true

require "minitest/autorun"
require "valkey/request_type"
require "valkey/utils"
require "valkey/commands/set_commands"

# Unit tests for set command request construction.
class TestSetCommandsUnit < Minitest::Test
  # Minimal command receiver that records dispatched requests.
  class FakeClient
    include Valkey::Commands::SetCommands

    attr_reader :captured_type, :captured_arguments, :captured_block

    def initialize(canned_reply = nil)
      @canned_reply = canned_reply
    end

    def send_command(request_type, command_arguments = [], &block)
      @captured_type = request_type
      @captured_arguments = command_arguments
      @captured_block = block
      block ? block.call(@canned_reply) : @canned_reply
    end
  end

  def test_sismember_if_exists
    client = FakeClient.new(1)

    client.sismember_if_exists("my_set", "member1")

    assert_equal Valkey::RequestType::SISMEMBER, client.captured_type
    assert_equal %w[my_set member1 XX], client.captured_arguments
  end

  def test_sismember_if_exists_with_xx_key_and_member
    client = FakeClient.new(1)

    client.sismember_if_exists("XX", "XX")

    assert_equal Valkey::RequestType::SISMEMBER, client.captured_type
    assert_equal %w[XX XX XX], client.captured_arguments
  end

  def test_sismember_if_exists_keeps_status_code
    client = FakeClient.new(-1)

    assert_equal(-1, client.sismember_if_exists("my_set", "member1"))
    refute_nil client.captured_block
    assert_equal(-1, client.captured_block.call(-1))
    assert_equal 0, client.captured_block.call(0)
  end

  def test_sismember_sends_two_args
    client = FakeClient.new(true)

    client.sismember("my_set", "member1")

    assert_equal Valkey::RequestType::SISMEMBER, client.captured_type
    assert_equal %w[my_set member1], client.captured_arguments
    assert_nil client.captured_block
  end
end
