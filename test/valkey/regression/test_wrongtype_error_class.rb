# frozen_string_literal: true

require "test_helper"

# Regression: WRONGTYPE server errors must surface as Valkey::WrongTypeError,
# not the base Valkey::CommandError. WrongTypeError is defined in
# lib/valkey/errors.rb but was never raised prior to this fix — every server
# error came out as bare CommandError, so code rescuing the specific class
# caught nothing.
class TestWrongTypeErrorClass < Minitest::Test
  def setup
    @port = Integer(ENV["VALKEY_PORT"] || 8201)
    @client = Valkey.new(host: "127.0.0.1", port: @port)
    @key = "wrongtype-regression-#{Process.pid}-#{rand(1_000_000)}"
    @client.del(@key)
  end

  def teardown
    @client&.del(@key)
    @client&.close
  end

  # WRONGTYPE on a string key targeted by a list command must raise the
  # specific subclass, not bare CommandError.
  def test_lpush_on_string_key_raises_wrong_type_error
    @client.set(@key, "x")

    error = assert_raises(Valkey::WrongTypeError) do
      @client.lpush(@key, "y")
    end

    assert_instance_of Valkey::WrongTypeError, error
    refute_equal Valkey::CommandError, error.class,
                 "Expected the specific WrongTypeError subclass, got bare CommandError"
  end

  # WrongTypeError inherits from CommandError, so existing
  # `rescue Valkey::CommandError` blocks in user code must still catch it.
  # This guards the "not a breaking change" promise.
  def test_wrong_type_error_rescuable_via_command_error
    @client.set(@key, "x")

    rescued = nil
    begin
      @client.lpush(@key, "y")
    rescue Valkey::CommandError => e
      rescued = e
    end

    refute_nil rescued, "WrongTypeError should be rescuable via CommandError superclass"
    assert_kind_of Valkey::WrongTypeError, rescued
    assert_kind_of Valkey::CommandError, rescued
  end

  # The upstream server error message ("WRONGTYPE Operation against a key
  # holding the wrong kind of value") must remain intact in .message so
  # log-scraping and existing string-match assertions keep working.
  def test_error_message_preserves_wrongtype_prefix
    @client.set(@key, "x")

    error = assert_raises(Valkey::WrongTypeError) do
      @client.lpush(@key, "y")
    end

    assert_match(/\AWRONGTYPE\b/, error.message,
                 "Error message should still begin with the raw WRONGTYPE prefix")
  end

  # Regression guard: other server errors (e.g. INCR on a non-numeric value
  # returns "ERR value is not an integer or out of range") must still raise
  # bare CommandError, not be mis-mapped to WrongTypeError. This proves the
  # dispatcher is conservative and only matches the WRONGTYPE prefix.
  def test_non_wrongtype_error_still_raises_command_error
    @client.set(@key, "not-a-number")

    error = assert_raises(Valkey::CommandError) do
      @client.incr(@key)
    end

    assert_equal Valkey::CommandError, error.class,
                 "Non-WRONGTYPE server errors should raise bare CommandError, " \
                 "not a more specific subclass"
    refute_kind_of Valkey::WrongTypeError, error
  end
end
