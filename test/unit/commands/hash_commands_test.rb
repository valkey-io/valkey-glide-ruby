# frozen_string_literal: true

require "minitest/autorun"
require "valkey/request_type"
require "valkey/commands/hash_commands"

# Unit tests for hash command request construction.
class TestHashCommandsUnit < Minitest::Test
  # Minimal command receiver that records dispatched requests.
  class FakeClient
    include Valkey::Commands::HashCommands

    attr_reader :captured_type, :captured_arguments

    def initialize(canned_reply = [])
      @canned_reply = canned_reply
    end

    def send_command(request_type, command_arguments = [], &block)
      @captured_type = request_type
      @captured_arguments = command_arguments
      block ? block.call(@canned_reply) : @canned_reply
    end
  end

  def test_hgetdel_builds_request_and_keeps_single_result_array
    client = FakeClient.new(["value"])

    assert_equal ["value"], client.hgetdel("hash", "field")
    assert_equal 628, client.captured_type
    assert_equal ["hash", "FIELDS", 1, "field"], client.captured_arguments
  end

  def test_hgetdel_flattens_one_level
    client = FakeClient.new

    client.hgetdel("hash", "f1", ["f2", ["f3"]])

    assert_equal Valkey::RequestType::HGETDEL, client.captured_type
    assert_equal ["hash", "FIELDS", 3, "f1", "f2", ["f3"]], client.captured_arguments
  end

  def test_hgetdel_forwards_zero_fields
    client = FakeClient.new

    client.hgetdel("hash")

    assert_equal Valkey::RequestType::HGETDEL, client.captured_type
    assert_equal ["hash", "FIELDS", 0], client.captured_arguments
  end
end
