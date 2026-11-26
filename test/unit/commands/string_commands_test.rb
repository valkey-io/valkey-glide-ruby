# frozen_string_literal: true

require "minitest/autorun"
require "valkey/errors"
require "valkey/request_type"
require "valkey/commands/string_commands"

# Unit tests for string command request construction.
class TestStringCommandsUnit < Minitest::Test
  # Input values
  STRING_VALUE = "value"
  BINARY_VALUE = "\x00\xFF".b.freeze
  ARRAY_VALUE = %w[a b].freeze

  # Expected arguments. Commands must use `to_s` to stringify values.
  STRING_ARG = "value"
  BINARY_ARG = "\x00\xFF".b.freeze
  ARRAY_ARG = "[\"a\", \"b\"]"

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

  def test_set
    assert_set(%w[key new])
  end

  def test_set_with_ifeq
    assert_set(%w[key new IFEQ current], ifeq: "current")
  end

  def test_set_with_ifeq_and_get
    assert_set(%w[key new IFEQ current GET], ifeq: "current", get: true)
  end

  def test_set_with_ifeq_values
    [
      [%w[current], "[\"current\"]"],
      [false, "false"],
      [0, "0"],
      ["", ""]
    ].each do |comparison, expected_sent_comparison|
      assert_set(["key", "new", "IFEQ", expected_sent_comparison], ifeq: comparison)
    end

    binary_comparison = "\xFF\x00".b
    assert_set(["key", "new", "IFEQ", binary_comparison], ifeq: binary_comparison) do |client|
      sent_comparison = client.captured_arguments.last
      assert_equal Encoding::BINARY, sent_comparison.encoding
      assert_equal binary_comparison.bytes, sent_comparison.bytes
    end
  end

  def test_set_with_ifne
    assert_set(%w[key new IFNE current], ifne: "current")
  end

  def test_set_with_ifne_and_get
    assert_set(%w[key new IFNE current GET], ifne: "current", get: true)
  end

  def test_set_with_ifne_values
    [
      [%w[a b], "[\"a\", \"b\"]"],
      [false, "false"],
      [0, "0"],
      ["", ""]
    ].each do |comparison, expected_sent_comparison|
      assert_set(["key", "new", "IFNE", expected_sent_comparison], ifne: comparison)
    end

    binary_comparison = "\xFF\x00".b
    assert_set(["key", "new", "IFNE", binary_comparison], ifne: binary_comparison) do |client|
      sent_comparison = client.captured_arguments.last
      assert_equal Encoding::BINARY, sent_comparison.encoding
      assert_equal binary_comparison.bytes, sent_comparison.bytes
    end
  end

  # DELEX
  # ---------------------------------------------------------------------------------------------

  def test_delex_ifeq
    assert_delex(key: "key", options: { ifeq: STRING_VALUE }, expected_args: ["key", "IFEQ", STRING_ARG])
  end

  def test_delex_ifne
    assert_delex(key: "key", options: { ifne: STRING_VALUE }, expected_args: ["key", "IFNE", STRING_ARG])
  end

  def test_delex_binary_value
    assert_delex(key: "key", options: { ifeq: BINARY_VALUE }, expected_args: ["key", "IFEQ", BINARY_ARG])
  end

  def test_delex_non_string_value
    assert_delex(key: "key", options: { ifeq: ARRAY_VALUE }, expected_args: ["key", "IFEQ", ARRAY_ARG])
  end

  def test_delex_propagates_client_error
    error = Valkey::CommandError.new("error")
    client = FakeClient.new(error: error)
    assert_same error, assert_raises(Valkey::CommandError) { client.delex("key", ifeq: STRING_VALUE) }
  end

  # DELIFEQ
  # ---------------------------------------------------------------------------------------------

  def test_delifeq
    assert_delifeq(key: "key", value: STRING_VALUE, expected_args: STRING_ARG)
  end

  def test_delifeq_binary_value
    assert_delifeq(key: "key", value: BINARY_VALUE, expected_args: BINARY_ARG)
  end

  def test_delifeq_non_string_value
    assert_delifeq(key: "key", value: ARRAY_VALUE, expected_args: ARRAY_ARG)
  end

  def test_delifeq_propagates_client_error
    error = Valkey::CommandError.new("error")
    client = FakeClient.new(error: error)
    assert_same error, assert_raises(Valkey::CommandError) { client.delifeq("key", STRING_VALUE) }
  end

  private

  def assert_set(expected_arguments, **options)
    reply = "OK"
    client = FakeClient.new(reply: reply)

    assert_same reply, client.set("key", "new", **options)
    assert_equal Valkey::RequestType::SET, client.captured_command
    assert_equal expected_arguments, client.captured_arguments

    yield client if block_given?
  end

  def assert_delex(key:, options:, expected_args:)
    client = FakeClient.new(reply: true)

    assert_equal true, client.delex(key, **options)
    assert_equal Valkey::RequestType::DEL_EX, client.captured_command
    assert_equal expected_args, client.captured_arguments
  end

  def assert_delifeq(key:, value:, expected_args:)
    client = FakeClient.new(reply: 0)

    assert_equal 0, client.delifeq(key, value)
    assert_equal Valkey::RequestType::DEL_IF_EQ, client.captured_command
    assert_equal [key, expected_args], client.captured_arguments
  end
end
