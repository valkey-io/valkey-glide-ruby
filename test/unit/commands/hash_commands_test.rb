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
  HSETEX_TTL_SECONDS = 60
  HSETEX_TTL_MILLISECONDS = 1500
  HSETEX_UNIX_TIME_SECONDS = 1_900_000_000
  HSETEX_UNIX_TIME_MILLISECONDS = 1_900_000_000_000
  HSETEX_FIELD_VALUES = %w[f1 v1 f2 v2].freeze
  HSETEX_FIELDS_ARGS = ["FIELDS", 2, *HSETEX_FIELD_VALUES].freeze
  HSETEX_DEPRECATION = /hsetex\(key, field, value, seconds\) is deprecated/

  def test_hsetex
    client = FakeClient.new(1)

    assert_equal 1, client.hsetex(HSETEX_KEY, *HSETEX_FIELD_VALUES)
    assert_equal Valkey::RequestType::HSETEX, client.captured_type
    assert_equal [HSETEX_KEY, *HSETEX_FIELDS_ARGS], client.captured_arguments
  end

  def test_hsetex_hash_attrs
    client = FakeClient.new(1)

    client.hsetex(HSETEX_KEY, { "f1" => "v1", "f2" => "v2" })

    assert_equal [HSETEX_KEY, *HSETEX_FIELDS_ARGS], client.captured_arguments
  end

  def test_hsetex_array_attrs
    client = FakeClient.new(1)

    client.hsetex(HSETEX_KEY, HSETEX_FIELD_VALUES)

    assert_equal [HSETEX_KEY, *HSETEX_FIELDS_ARGS], client.captured_arguments
  end

  def test_hsetex_expiry_options
    {
      { ex: HSETEX_TTL_SECONDS } => ["EX", HSETEX_TTL_SECONDS],
      { px: HSETEX_TTL_MILLISECONDS } => ["PX", HSETEX_TTL_MILLISECONDS],
      { exat: HSETEX_UNIX_TIME_SECONDS } => ["EXAT", HSETEX_UNIX_TIME_SECONDS],
      { pxat: HSETEX_UNIX_TIME_MILLISECONDS } => ["PXAT", HSETEX_UNIX_TIME_MILLISECONDS],
      { keepttl: true } => ["KEEPTTL"]
    }.each do |options, expected_args|
      client = FakeClient.new(1)

      client.hsetex(HSETEX_KEY, *HSETEX_FIELD_VALUES, **options)

      assert_equal [HSETEX_KEY, *expected_args, *HSETEX_FIELDS_ARGS], client.captured_arguments, options.inspect
    end
  end

  def test_hsetex_conditions
    { nx: "NX", xx: "XX", fnx: "FNX", fxx: "FXX" }.each do |option, token|
      client = FakeClient.new(1)

      client.hsetex(HSETEX_KEY, *HSETEX_FIELD_VALUES, option => true)

      assert_equal [HSETEX_KEY, token, *HSETEX_FIELDS_ARGS], client.captured_arguments, option.inspect
    end
  end

  def test_hsetex_option_order
    client = FakeClient.new(1)

    client.hsetex(HSETEX_KEY, *HSETEX_FIELD_VALUES, ex: HSETEX_TTL_SECONDS, fnx: true, nx: true)

    assert_equal [HSETEX_KEY, "NX", "FNX", "EX", HSETEX_TTL_SECONDS, *HSETEX_FIELDS_ARGS], client.captured_arguments
  end

  def test_hsetex_options_disabled
    client = FakeClient.new(1)

    client.hsetex(HSETEX_KEY, *HSETEX_FIELD_VALUES, nx: false, xx: nil, fnx: false, fxx: nil, keepttl: false)

    assert_equal [HSETEX_KEY, *HSETEX_FIELDS_ARGS], client.captured_arguments
  end

  def test_hsetex_odd_attrs
    [
      %w[f1 v1 f2 v2 f3],
      %w[f1],
      [%w[f1 v1], "f2"]
    ].each do |attrs|
      client = FakeClient.new(1)

      error = assert_raises(ArgumentError, attrs.inspect) { client.hsetex(HSETEX_KEY, *attrs) }

      assert_match(/requires field-value pairs/, error.message, attrs.inspect)
      assert_nil client.captured_type, attrs.inspect
    end
  end

  def test_hsetex_deprecated_form
    client = FakeClient.new(1)
    result = nil

    _, warning = capture_io { result = client.hsetex(HSETEX_KEY, "f1", "v1", HSETEX_TTL_SECONDS) }

    assert_equal 1, result
    assert_equal [HSETEX_KEY, "EX", HSETEX_TTL_SECONDS, "FIELDS", 1, "f1", "v1"], client.captured_arguments
    assert_match HSETEX_DEPRECATION, warning
    assert_includes warning, __FILE__
  end

  def test_hsetex_deprecated_form_array_value
    client = FakeClient.new(1)

    _, warning = capture_io { client.hsetex(HSETEX_KEY, "f1", ["v1"], HSETEX_TTL_SECONDS) }

    assert_equal [HSETEX_KEY, "EX", HSETEX_TTL_SECONDS, "FIELDS", 1, "f1", ["v1"]], client.captured_arguments
    assert_match HSETEX_DEPRECATION, warning
  end

  def test_hsetex_three_attrs_with_pair_array
    client = FakeClient.new(1)

    _, warning = capture_io { client.hsetex(HSETEX_KEY, %w[f1 v1], "f2", "v2") }

    assert_equal [HSETEX_KEY, *HSETEX_FIELDS_ARGS], client.captured_arguments
    assert_empty warning
  end

  def test_hsetex_deprecated_form_with_options
    %i[nx xx fnx fxx ex px exat pxat keepttl].each do |option|
      client = FakeClient.new(1)

      error = nil
      _, warning = capture_io do
        error = assert_raises(ArgumentError, option.inspect) do
          client.hsetex(HSETEX_KEY, "f1", "v1", HSETEX_TTL_SECONDS, option => false)
        end
      end

      assert_match(/does not accept options/, error.message, option.inspect)
      assert_nil client.captured_type, option.inspect
      assert_empty warning, option.inspect
    end
  end
end
