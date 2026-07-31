# frozen_string_literal: true

require "minitest/autorun"
require "securerandom"

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__) unless ENV["TEST_INSTALLED_GEM"]
require "valkey"

# Regression tests for the remaining blocking commands surfaced by the
# rc3 blocker sweep alongside blpop/brpop (see test_blocking_list_commands.rb).
#
# Covered: blmove, blmpop, bzpopmax, bzpopmin, bzmpop.
#
# Each command is exercised twice against a live server (127.0.0.1:8100):
#   * happy path -- data is present, blocking call returns immediately
#   * timeout path -- key is missing, call with timeout: 1 returns nil ~1s
#
# Bugs to catch (same failure modes that broke blpop):
#   (a) NoMethodError from a stale send_blocking_command dispatch
#   (b) TypeError from passing a Symbol as the RequestType command_type
#   (c) Valkey::CommandError "Couldn't fetch command type" -- glide-core
#       has no get_command mapping for this RequestType (e.g. BRPOPLPUSH)
#   (d) Server-side wrong-number-of-arguments -- a Symbol accidentally
#       shipped inside the args array becomes a bogus extra RESP token
class TestOtherBlockingCommandsRegression < Minitest::Test
  PORT = Integer(ENV["REGRESSION_PORT"] || 8100)
  HOST = ENV["REGRESSION_HOST"] || "127.0.0.1"

  def setup
    @client = Valkey.new(host: HOST, port: PORT)
    @prefix = "regression:other-blocking:#{SecureRandom.hex(4)}:"
  end

  def teardown
    @client&.close
  end

  def key(name)
    "#{@prefix}#{name}"
  end

  # -------------------- blmove --------------------

  def test_blmove_happy_path_returns_immediately
    src = key("blmove:src")
    dst = key("blmove:dst")
    @client.rpush(src, "elem")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @client.blmove(src, dst, "LEFT", "RIGHT", timeout: 1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_equal "elem", result
    assert_equal ["elem"], @client.lrange(dst, 0, -1)
    assert_operator elapsed, :<, 0.5, "should return immediately (got #{elapsed}s)"
  end

  def test_blmove_timeout_path_returns_nil
    src = key("blmove:missing-src")
    dst = key("blmove:missing-dst")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @client.blmove(src, dst, "LEFT", "RIGHT", timeout: 1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_nil result
    assert_operator elapsed, :>=, 0.8, "should block for ~1s (got #{elapsed}s)"
    assert_operator elapsed, :<, 3.0, "should not block much past 1s (got #{elapsed}s)"
  end

  # -------------------- blmpop --------------------

  def test_blmpop_happy_path_returns_immediately
    k = key("blmpop:list")
    @client.rpush(k, "a")
    @client.rpush(k, "b")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @client.blmpop(1.0, k, count: 2)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    # Expected: [key, [elems...]]
    assert_kind_of Array, result
    assert_equal k, result[0]
    assert_equal %w[a b], result[1]
    assert_operator elapsed, :<, 0.5, "should return immediately (got #{elapsed}s)"
  end

  def test_blmpop_timeout_path_returns_nil
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @client.blmpop(1.0, key("blmpop:missing"))
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_nil result
    assert_operator elapsed, :>=, 0.8, "should block for ~1s (got #{elapsed}s)"
    assert_operator elapsed, :<, 3.0, "should not block much past 1s (got #{elapsed}s)"
  end

  # -------------------- bzpopmax --------------------

  def test_bzpopmax_happy_path_returns_immediately
    k = key("bzpopmax:zset")
    @client.zadd(k, [[1.0, "low"], [3.0, "high"], [2.0, "mid"]])

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @client.bzpopmax(k, timeout: 1.0)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_equal [k, "high", 3.0], result
    assert_operator elapsed, :<, 0.5, "should return immediately (got #{elapsed}s)"
  end

  def test_bzpopmax_timeout_path_returns_nil
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @client.bzpopmax(key("bzpopmax:missing"), timeout: 1.0)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_nil result
    assert_operator elapsed, :>=, 0.8, "should block for ~1s (got #{elapsed}s)"
    assert_operator elapsed, :<, 3.0, "should not block much past 1s (got #{elapsed}s)"
  end

  # -------------------- bzpopmin --------------------

  def test_bzpopmin_happy_path_returns_immediately
    k = key("bzpopmin:zset")
    @client.zadd(k, [[1.0, "low"], [3.0, "high"], [2.0, "mid"]])

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @client.bzpopmin(k, timeout: 1.0)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_equal [k, "low", 1.0], result
    assert_operator elapsed, :<, 0.5, "should return immediately (got #{elapsed}s)"
  end

  def test_bzpopmin_timeout_path_returns_nil
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @client.bzpopmin(key("bzpopmin:missing"), timeout: 1.0)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_nil result
    assert_operator elapsed, :>=, 0.8, "should block for ~1s (got #{elapsed}s)"
    assert_operator elapsed, :<, 3.0, "should not block much past 1s (got #{elapsed}s)"
  end

  # -------------------- bzmpop --------------------

  def test_bzmpop_happy_path_returns_immediately
    k = key("bzmpop:zset")
    @client.zadd(k, [[1.0, "a"], [2.0, "b"], [3.0, "c"]])

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @client.bzmpop(1.0, k, modifier: "MAX", count: 2)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    # Expected: [key, [[member, score], ...]]
    assert_kind_of Array, result
    assert_equal k, result[0]
    assert_equal [["c", 3.0], ["b", 2.0]], result[1]
    assert_operator elapsed, :<, 0.5, "should return immediately (got #{elapsed}s)"
  end

  def test_bzmpop_timeout_path_returns_nil
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @client.bzmpop(1.0, key("bzmpop:missing"), modifier: "MIN", count: 1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_nil result
    assert_operator elapsed, :>=, 0.8, "should block for ~1s (got #{elapsed}s)"
    assert_operator elapsed, :<, 3.0, "should not block much past 1s (got #{elapsed}s)"
  end
end
