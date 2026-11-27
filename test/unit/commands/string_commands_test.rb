# frozen_string_literal: true

require "minitest/autorun"
require "valkey/errors"
require "valkey/request_type"
require "valkey/commands/string_commands"

# Unit tests for string command request construction.
class TestStringCommandsUnit < Minitest::Test
  ARRAY = %w[a b].freeze
  ARRAY_STRING = "[\"a\", \"b\"]"
  BYTES = "\x00\xFF".b.freeze
  INTEGER = 10
  STRING = "value"

  KEY = "key"
  OK = "OK"

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
    assert_delex(KEY, ifeq: STRING, expected: [KEY, "IFEQ", STRING])
    assert_delex(KEY, ifeq: BYTES, expected: [KEY, "IFEQ", BYTES])
    assert_delex(KEY, ifeq: ARRAY, expected: [KEY, "IFEQ", ARRAY_STRING])
    assert_delex(KEY, ifne: STRING, expected: [KEY, "IFNE", STRING])
    assert_delex(KEY, ifne: BYTES, expected: [KEY, "IFNE", BYTES])
    assert_delex(KEY, ifne: ARRAY, expected: [KEY, "IFNE", ARRAY_STRING])
    assert_delex(KEY, ifeq: nil, ifne: nil, expected: [KEY])
  end

  def test_delifeq
    assert_delifeq(KEY, STRING, expected: [KEY, STRING])
    assert_delifeq(KEY, BYTES, expected: [KEY, BYTES])
    assert_delifeq(KEY, ARRAY, expected: [KEY, ARRAY_STRING])
    assert_delifeq(KEY, nil, expected: [KEY, ""])
  end

  def test_set
    # values
    assert_set(KEY, STRING, expected: [KEY, STRING])
    assert_set(KEY, BYTES, expected: [KEY, BYTES])
    assert_set(KEY, ARRAY, expected: [KEY, ARRAY_STRING])
    assert_set(KEY, nil, expected: [KEY, ""])

    # expiration
    assert_set(KEY, STRING, ex: INTEGER, expected: [KEY, STRING, "EX", INTEGER])
    assert_set(KEY, STRING, px: INTEGER, expected: [KEY, STRING, "PX", INTEGER])
    assert_set(KEY, STRING, exat: INTEGER, expected: [KEY, STRING, "EXAT", INTEGER])
    assert_set(KEY, STRING, pxat: INTEGER, expected: [KEY, STRING, "PXAT", INTEGER])
    assert_set(KEY, STRING, keepttl: true, expected: [KEY, STRING, "KEEPTTL"])
    assert_set(KEY, STRING, ex: false, px: false, exat: false, pxat: false, keepttl: false, expected: [KEY, STRING])
    assert_set(KEY, STRING, ex: nil, px: nil, exat: nil, pxat: nil, keepttl: nil, expected: [KEY, STRING])

    # existence conditions
    assert_set(KEY, STRING, nx: true, expected: [KEY, STRING, "NX"])
    assert_set(KEY, STRING, xx: true, expected: [KEY, STRING, "XX"])
    assert_set(KEY, STRING, nx: false, xx: false, expected: [KEY, STRING])
    assert_set(KEY, STRING, nx: nil, xx: nil, expected: [KEY, STRING])

    # value conditions
    assert_set(KEY, STRING, ifeq: STRING, expected: [KEY, STRING, "IFEQ", STRING])
    assert_set(KEY, STRING, ifeq: BYTES, expected: [KEY, STRING, "IFEQ", BYTES])
    assert_set(KEY, STRING, ifeq: ARRAY, expected: [KEY, STRING, "IFEQ", ARRAY_STRING])
    assert_set(KEY, STRING, ifne: STRING, expected: [KEY, STRING, "IFNE", STRING])
    assert_set(KEY, STRING, ifne: BYTES, expected: [KEY, STRING, "IFNE", BYTES])
    assert_set(KEY, STRING, ifne: ARRAY, expected: [KEY, STRING, "IFNE", ARRAY_STRING])
    assert_set(KEY, STRING, ifeq: nil, ifne: nil, expected: [KEY, STRING])

    # get
    assert_set(KEY, STRING, get: true, expected: [KEY, STRING, "GET"])
    assert_set(KEY, STRING, get: false, expected: [KEY, STRING])
    assert_set(KEY, STRING, get: nil, expected: [KEY, STRING])

    # combined options
    assert_set(
      KEY, STRING,
      get: true, ifeq: STRING, ex: INTEGER,
      expected: [KEY, STRING, "EX", INTEGER, "IFEQ", STRING, "GET"]
    )
    assert_set(
      KEY, STRING,
      get: true, xx: true, keepttl: true,
      expected: [KEY, STRING, "XX", "KEEPTTL", "GET"]
    )
  end

  def test_propagates_client_error
    error = Valkey::CommandError.new("error")
    client = FakeClient.new(error: error)

    assert_same error, assert_raises(Valkey::CommandError) { client.delex(KEY, ifeq: STRING) }
    assert_same error, assert_raises(Valkey::CommandError) { client.delifeq(KEY, STRING) }
    assert_same error, assert_raises(Valkey::CommandError) { client.set(KEY, STRING, ifeq: STRING) }
  end

  private

  # Assert that `delex` called with the given arguments sends the expected command arguments.
  def assert_delex(*args, expected:, **options)
    client = FakeClient.new(reply: true)

    assert_equal true, client.delex(*args, **options)
    assert_equal Valkey::RequestType::DEL_EX, client.captured_command
    assert_equal expected, client.captured_arguments
  end

  # Assert that `delifeq` called with the given arguments sends the expected command arguments.
  def assert_delifeq(*args, expected:)
    client = FakeClient.new(reply: true)

    assert_equal true, client.delifeq(*args)
    assert_equal Valkey::RequestType::DEL_IF_EQ, client.captured_command
    assert_equal expected, client.captured_arguments
  end

  # Assert that `set` called with the given arguments sends the expected command arguments.
  def assert_set(*args, expected:, **options)
    client = FakeClient.new(reply: OK)

    assert_equal OK, client.set(*args, **options)
    assert_equal Valkey::RequestType::SET, client.captured_command
    assert_equal expected, client.captured_arguments
  end
end
