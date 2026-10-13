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

  def test_hgetdel
    client = FakeClient.new(["value"])
    expected_hash = "hash"
    expected_field = "field"
    expected_fields_count = 1

    assert_equal ["value"], client.hgetdel(expected_hash, expected_field)
    assert_equal Valkey::RequestType::HGETDEL, client.captured_type
    assert_equal [expected_hash, "FIELDS", expected_fields_count, expected_field], client.captured_arguments
  end

  def test_hgetdel_array_fields
    client = FakeClient.new
    expected_hash = "hash"
    expected_fields = %w[f1 f2]

    client.hgetdel(expected_hash, expected_fields)

    assert_equal Valkey::RequestType::HGETDEL, client.captured_type
    assert_equal [expected_hash, "FIELDS", expected_fields.length, *expected_fields], client.captured_arguments
  end
end
