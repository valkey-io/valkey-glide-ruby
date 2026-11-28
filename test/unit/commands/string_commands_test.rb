# frozen_string_literal: true

require "minitest/autorun"
require "valkey/errors"
require "valkey/request_type"
require "valkey/commands/string_commands"

# Unit tests for string command request construction.
class TestStringCommandsUnit < Minitest::Test
  ARRAY = %w[a b].freeze
  ARRAY_STR =  "[\"a\", \"b\"]"
  BYTES = "\x00\xFF".b.freeze
  INTEGER = 10
  INTEGER_STR = "10"
  TEXT = "value"

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

  def test_delex
    assert_delex(TEXT, ifeq: TEXT, expected: [TEXT, "IFEQ", TEXT])
    assert_delex(BYTES, ifne: TEXT, expected: [BYTES, "IFNE", TEXT])

    assert_delex(TEXT, ifeq: BYTES, expected: [TEXT, "IFEQ", BYTES])
    assert_delex(TEXT, ifeq: ARRAY, expected: [TEXT, "IFEQ", ARRAY_STR])
    assert_delex(TEXT, ifeq: nil, expected: [TEXT])

    assert_delex(TEXT, ifne: BYTES, expected: [TEXT, "IFNE", BYTES])
    assert_delex(TEXT, ifne: ARRAY, expected: [TEXT, "IFNE", ARRAY_STR])
    assert_delex(TEXT, ifne: nil, expected: [TEXT])
  end

  def test_delifeq
    assert_delifeq(TEXT, TEXT, expected: [TEXT, TEXT])
    assert_delifeq(BYTES, TEXT, expected: [BYTES, TEXT])

    assert_delifeq(TEXT, BYTES, expected: [TEXT, BYTES])
    assert_delifeq(TEXT, ARRAY, expected: [TEXT, ARRAY_STR])
    assert_delifeq(TEXT, nil, expected: [TEXT, ""])
  end

  def test_set
    assert_set(TEXT, TEXT, expected: [TEXT, TEXT])
    assert_set(BYTES, TEXT, expected: [BYTES, TEXT])

    assert_set(TEXT, BYTES, expected: [TEXT, BYTES])
    assert_set(TEXT, ARRAY, expected: [TEXT, ARRAY_STR])
    assert_set(TEXT, nil, expected: [TEXT, ""])

    assert_set(TEXT, TEXT, ex: INTEGER, expected: [TEXT, TEXT, "EX", INTEGER])
    assert_set(TEXT, TEXT, ex: INTEGER_STR, expected: [TEXT, TEXT, "EX", INTEGER])
    assert_set(TEXT, TEXT, px: INTEGER, expected: [TEXT, TEXT, "PX", INTEGER])
    assert_set(TEXT, TEXT, px: INTEGER_STR, expected: [TEXT, TEXT, "PX", INTEGER])
    assert_set(TEXT, TEXT, exat: INTEGER, expected: [TEXT, TEXT, "EXAT", INTEGER])
    assert_set(TEXT, TEXT, exat: INTEGER_STR, expected: [TEXT, TEXT, "EXAT", INTEGER])
    assert_set(TEXT, TEXT, pxat: INTEGER, expected: [TEXT, TEXT, "PXAT", INTEGER])
    assert_set(TEXT, TEXT, pxat: INTEGER_STR, expected: [TEXT, TEXT, "PXAT", INTEGER])
    assert_set(TEXT, TEXT, keepttl: true, expected: [TEXT, TEXT, "KEEPTTL"])
    assert_set(TEXT, TEXT, ex: false, px: false, exat: false, pxat: false, keepttl: false, expected: [TEXT, TEXT])
    assert_set(TEXT, TEXT, ex: nil, px: nil, exat: nil, pxat: nil, keepttl: nil, expected: [TEXT, TEXT])

    assert_set(TEXT, TEXT, nx: true, expected: [TEXT, TEXT, "NX"])
    assert_set(TEXT, TEXT, xx: true, expected: [TEXT, TEXT, "XX"])
    assert_set(TEXT, TEXT, nx: false, xx: false, expected: [TEXT, TEXT])
    assert_set(TEXT, TEXT, nx: nil, xx: nil, expected: [TEXT, TEXT])

    assert_set(TEXT, TEXT, ifeq: TEXT, expected: [TEXT, TEXT, "IFEQ", TEXT])
    assert_set(TEXT, TEXT, ifeq: BYTES, expected: [TEXT, TEXT, "IFEQ", BYTES])
    assert_set(TEXT, TEXT, ifeq: ARRAY, expected: [TEXT, TEXT, "IFEQ", ARRAY_STR])
    assert_set(TEXT, TEXT, ifne: TEXT, expected: [TEXT, TEXT, "IFNE", TEXT])
    assert_set(TEXT, TEXT, ifne: BYTES, expected: [TEXT, TEXT, "IFNE", BYTES])
    assert_set(TEXT, TEXT, ifne: ARRAY, expected: [TEXT, TEXT, "IFNE", ARRAY_STR])
    assert_set(TEXT, TEXT, ifeq: false, expected: [TEXT, TEXT, "IFEQ", "false"])
    assert_set(TEXT, TEXT, ifne: false, expected: [TEXT, TEXT, "IFNE", "false"])
    assert_set(TEXT, TEXT, ifeq: nil, ifne: nil, expected: [TEXT, TEXT])

    assert_set(TEXT, TEXT, get: true, expected: [TEXT, TEXT, "GET"])
    assert_set(TEXT, TEXT, get: false, expected: [TEXT, TEXT])
    assert_set(TEXT, TEXT, get: nil, expected: [TEXT, TEXT])

    assert_set(
      TEXT, TEXT,
      get: true, ifeq: TEXT, ex: INTEGER,
      expected: [TEXT, TEXT, "EX", INTEGER, "IFEQ", TEXT, "GET"]
    )
    assert_set(
      TEXT, TEXT,
      get: true, xx: true, keepttl: true,
      expected: [TEXT, TEXT, "XX", "KEEPTTL", "GET"]
    )
  end

  def test_propagates_client_error
    error = Valkey::CommandError.new("error")
    client = FakeClient.new(error: error)

    assert_same error, assert_raises(Valkey::CommandError) { client.delex(TEXT, ifeq: TEXT) }
    assert_same error, assert_raises(Valkey::CommandError) { client.delifeq(TEXT, TEXT) }
    assert_same error, assert_raises(Valkey::CommandError) { client.set(TEXT, TEXT, ifeq: TEXT) }
  end

  private

  def assert_delex(*args, expected:, **options)
    assert_command(:delex, Valkey::RequestType::DEL_EX, *args, expected: expected, **options)
  end

  def assert_delifeq(*args, expected:)
    assert_command(:delifeq, Valkey::RequestType::DEL_IF_EQ, *args, expected: expected)
  end

  def assert_set(*args, expected:, **options)
    assert_command(:set, Valkey::RequestType::SET, *args, expected: expected, **options)
  end

  # Assert that calling the command with the given arguments sends the
  # expected request type and argument and returns the reply unchanged.
  def assert_command(command, request_type, *args, expected:, **options)
    reply = Object.new
    client = FakeClient.new(reply: reply)

    assert_same reply, client.public_send(command, *args, **options)
    assert_equal request_type, client.captured_command
    assert_equal expected, client.captured_arguments
  end
end
