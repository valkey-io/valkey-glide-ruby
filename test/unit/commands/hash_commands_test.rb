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

    expected_fields = %w[f1 f2]
    assert_equal ["value"], client.hgetdel(expected_hash, expected_fields)
    assert_equal Valkey::RequestType::HGETDEL, client.captured_type
    assert_equal [expected_hash, "FIELDS", expected_fields.length, *expected_fields], client.captured_arguments
  end

  HSETEX_KEY = "hash"
  HSETEX_FIELD = "field"
  HSETEX_VALUE = "value"
  HSETEX_TTL_SECONDS = 60
  HSETEX_FIELDS_COUNT = 1
  HSETEX_TRAILING_ARGS = [
    "EX", HSETEX_TTL_SECONDS, "FIELDS", HSETEX_FIELDS_COUNT, HSETEX_FIELD, HSETEX_VALUE
  ].freeze

  def test_hsetex
    client = FakeClient.new(1)

    assert_equal 1, client.hsetex(HSETEX_KEY, HSETEX_FIELD, HSETEX_VALUE, HSETEX_TTL_SECONDS)
    assert_equal Valkey::RequestType::HSETEX, client.captured_type
    assert_equal [HSETEX_KEY, *HSETEX_TRAILING_ARGS], client.captured_arguments
  end

  def test_hsetex_nx
    client = FakeClient.new(1)

    client.hsetex(HSETEX_KEY, HSETEX_FIELD, HSETEX_VALUE, HSETEX_TTL_SECONDS, nx: true)

    assert_equal [HSETEX_KEY, "NX", *HSETEX_TRAILING_ARGS], client.captured_arguments
  end

  def test_hsetex_xx
    client = FakeClient.new(1)

    client.hsetex(HSETEX_KEY, HSETEX_FIELD, HSETEX_VALUE, HSETEX_TTL_SECONDS, xx: true)

    assert_equal [HSETEX_KEY, "XX", *HSETEX_TRAILING_ARGS], client.captured_arguments
  end

  def test_hsetex_fnx
    client = FakeClient.new(1)

    client.hsetex(HSETEX_KEY, HSETEX_FIELD, HSETEX_VALUE, HSETEX_TTL_SECONDS, fnx: true)

    assert_equal [HSETEX_KEY, "FNX", *HSETEX_TRAILING_ARGS], client.captured_arguments
  end

  def test_hsetex_fxx
    client = FakeClient.new(1)

    client.hsetex(HSETEX_KEY, HSETEX_FIELD, HSETEX_VALUE, HSETEX_TTL_SECONDS, fxx: true)

    assert_equal [HSETEX_KEY, "FXX", *HSETEX_TRAILING_ARGS], client.captured_arguments
  end

  def test_hsetex_key_and_field_conditions
    client = FakeClient.new(1)

    client.hsetex(HSETEX_KEY, HSETEX_FIELD, HSETEX_VALUE, HSETEX_TTL_SECONDS, fnx: true, nx: true)

    assert_equal [HSETEX_KEY, "NX", "FNX", *HSETEX_TRAILING_ARGS], client.captured_arguments
  end

  def test_hsetex_conditions_disabled
    client = FakeClient.new(1)

    client.hsetex(HSETEX_KEY, HSETEX_FIELD, HSETEX_VALUE, HSETEX_TTL_SECONDS, nx: false, xx: nil, fnx: false, fxx: nil)

    assert_equal [HSETEX_KEY, *HSETEX_TRAILING_ARGS], client.captured_arguments
  end
end
