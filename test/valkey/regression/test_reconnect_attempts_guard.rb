# frozen_string_literal: true

require "test_helper"

# Regression tests for the reconnect_attempts: 0 guard.
#
# Setting reconnect_attempts: 0 hangs the process indefinitely below the FFI
# boundary because of an integer underflow in glide-core's retry_strategies.rs
# (0usize - 1 wraps). The Ruby-side guard converts that hang into a fast
# ArgumentError. See https://github.com/valkey-io/valkey-glide/issues/6379.
class TestReconnectAttemptsGuard < Minitest::Test
  PORT = Integer(ENV["VALKEY_PORT"] || 8102)

  def test_reconnect_attempts_zero_raises_argument_error
    error = assert_raises(ArgumentError) do
      Valkey.new(host: "127.0.0.1", port: PORT, reconnect_attempts: 0)
    end
    # Message must reference the upstream issue so operators can trace the
    # rationale — future removal of this guard hinges on that issue closing.
    assert_match(/6379/, error.message)
  end

  def test_reconnect_attempts_one_still_works
    client = Valkey.new(host: "127.0.0.1", port: PORT, reconnect_attempts: 1)
    assert_equal "PONG", client.ping
  ensure
    client&.close
  end

  def test_reconnect_attempts_five_still_works
    client = Valkey.new(host: "127.0.0.1", port: PORT, reconnect_attempts: 5)
    assert_equal "PONG", client.ping
  ensure
    client&.close
  end

  def test_negative_reconnect_attempts_still_raises_original_message
    # The pre-existing non-negative check must remain intact — the new zero
    # guard should not shadow it, so operators still see the specific
    # "non-negative" wording for -1, -5, etc.
    error = assert_raises(ArgumentError) do
      Valkey.new(host: "127.0.0.1", port: PORT, reconnect_attempts: -1)
    end
    assert_match(/must be non-negative/, error.message)
  end
end
