# frozen_string_literal: true

require "minitest/autorun"
require "securerandom"

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__) unless ENV["TEST_INSTALLED_GEM"]
require "valkey"

# Regression tests for blpop/brpop.
#
# Bug: lib/valkey/commands/list_commands.rb called a non-existent
# send_blocking_command method, causing NoMethodError for every blocking-list
# command form. glide-core dispatches BLPOP/BRPOP with the timeout as the last
# positional arg via the ordinary send_command, so no separate blocking
# dispatch is needed.
#
# brpoplpush is intentionally NOT exposed by the wrapper: glide-core has no
# get_command mapping for RequestType::BRPopLPush, so the command cannot
# dispatch through the FFI stack. Every other GLIDE binding also omits it.
# Users needing atomic blocking pop-and-move should use blmove.
#
# Requires a standalone Valkey/Redis server at 127.0.0.1:8100.
class TestBlockingListCommandsRegression < Minitest::Test
  PORT = Integer(ENV["REGRESSION_PORT"] || 8100)
  HOST = ENV["REGRESSION_HOST"] || "127.0.0.1"

  def setup
    @client = Valkey.new(host: HOST, port: PORT)
    @prefix = "regression:blpop:#{SecureRandom.hex(4)}:"
  end

  def teardown
    @client&.close
  end

  def key(name)
    "#{@prefix}#{name}"
  end

  # 1. blpop on missing key with timeout:1 returns nil after ~1s
  def test_blpop_on_missing_key_returns_nil_after_timeout
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @client.blpop(key("missing"), timeout: 1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_nil result
    assert_operator elapsed, :>=, 0.8, "should block for ~1s (got #{elapsed}s)"
    assert_operator elapsed, :<, 3.0, "should not block much longer than 1s (got #{elapsed}s)"
  end

  # 2. blpop on populated key returns [key, value] immediately (< 100ms)
  def test_blpop_on_populated_key_returns_immediately
    k = key("populated")
    @client.rpush(k, "value1")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @client.blpop(k, timeout: 1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_equal [k, "value1"], result
    assert_operator elapsed, :<, 0.5, "should return immediately (got #{elapsed}s)"
  end

  # 3. brpop on missing key with timeout:1 returns nil
  def test_brpop_on_missing_key_returns_nil_after_timeout
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @client.brpop(key("missing-r"), timeout: 1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_nil result
    assert_operator elapsed, :>=, 0.8, "should block for ~1s (got #{elapsed}s)"
    assert_operator elapsed, :<, 3.0, "should not block much longer than 1s (got #{elapsed}s)"
  end

  # 4. brpop on populated key returns [key, value]
  def test_brpop_on_populated_key_returns_immediately
    k = key("populated-r")
    @client.rpush(k, "value1")
    @client.rpush(k, "value2")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @client.brpop(k, timeout: 1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    # brpop pops from the tail
    assert_equal [k, "value2"], result
    assert_operator elapsed, :<, 0.5, "should return immediately (got #{elapsed}s)"
  end

  # 5. brpoplpush is not exposed by the wrapper (see file header for rationale).
  def test_brpoplpush_is_not_exposed
    v = Valkey.new(host: '127.0.0.1', port: 8100)
    refute v.respond_to?(:brpoplpush),
           'brpoplpush should not be exposed until glide-core adds the ' \
           'RequestType::BRPopLPush get_command mapping (parity with other clients)'
  end

  # 6. Positional-timeout parity form -- v.blpop('k', 1) -- is not supported
  # by the current _bpop helper (only :timeout keyword is honoured), so a
  # trailing Integer is dispatched as an extra key and the command blocks
  # indefinitely. Dropped per task guidance: do NOT expand fix scope.
  def test_blpop_positional_timeout_parity
    skip "positional-timeout form (blpop('k', 1)) not supported by current _bpop helper; tracked separately"
  end
end
