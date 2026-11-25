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

  def test_delifeq
    assert_delifeq(key: "key", value: "value", expected_sent_value: "value")
  end

  def test_delifeq_non_string_value
    # non-string values are stringified
    assert_delifeq(key: "key", value: %w[a b], expected_sent_value: "[\"a\", \"b\"]")
  end

  def test_delifeq_stringifies_nil_value
    assert_delifeq(key: "key", value: nil, expected_sent_value: "")
  end

  def test_delifeq_propagates_client_error
    error = Valkey::CommandError.new("error")
    client = FakeClient.new(error: error)

    raised_error = assert_raises(Valkey::CommandError) { client.delifeq("key", "value") }

    assert_same error, raised_error
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

  def assert_delifeq(key:, value:, expected_sent_value:)
    client = FakeClient.new(reply: 0)

    assert_equal 0, client.delifeq(key, value)
    assert_equal Valkey::RequestType::DEL_IF_EQ, client.captured_command
    assert_equal [key, expected_sent_value], client.captured_arguments

    client
  end
end
