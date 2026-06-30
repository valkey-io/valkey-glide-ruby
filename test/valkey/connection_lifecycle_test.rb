# frozen_string_literal: true

# Connection-lifecycle tests: behavior on close and on connection timeout.
#
# Mirrors the sibling GLIDE clients:
#   - test 4 (closed client): go/integTest/standalone_commands_test.go ->
#     TestPing_ClosedClient; python .../test_async_client.py ->
#     test_closed_client_raises_error (asserts "the client is closed")
#   - test 5 (recreation): python -> test_client_recreation_after_close
#   - test 6 (unavailable host): python -> test_connection_timeout_on_unavailable_host
#   - test 7 (blocked server): node/tests/GlideClient.test.ts:1279
#     "should handle connection timeout when client is blocked by long-running command";
#     python -> test_connection_timeout_when_client_is_blocked
#
# All are standalone-shaped and skipped in cluster mode.
module ValkeyTests
  module ConnectionLifecycle
    # should raise a connection error stating the client is closed when a
    # command is issued after close
    def test_closed_client_raises_error
      skip("connection lifecycle tests only run on standalone mode") if cluster_mode?

      client = _new_client
      client.close

      error = assert_raises(Valkey::ConnectionError) { client.set("foo", "bar") }
      assert_match(/the client is closed/, error.message)
    end

    # should let a new client connect and round-trip set/get after a previous
    # client was closed (the shared FFI pipe stays valid across lifecycles)
    def test_client_recreation_after_close
      skip("connection lifecycle tests only run on standalone mode") if cluster_mode?

      key = "lifecycle:recreate"

      client1 = _new_client
      assert_equal "OK", client1.set(key, "v1")
      assert_equal "v1", client1.get(key)
      client1.close

      client2 = _new_client
      assert_equal "OK", client2.set(key, "v2")
      assert_equal "v2", client2.get(key)
      client2.del(key)
      client2.close
    end

    # should fail fast (within ~2.5x the connect timeout) instead of hanging
    # when connecting to an unreachable host
    def test_connection_timeout_on_unavailable_host
      skip("connection lifecycle tests only run on standalone mode") if cluster_mode?

      connect_timeout = 1.0
      # 192.0.2.1 is TEST-NET-1 (RFC 5737), reserved and unroutable, so the
      # connect attempt hangs until the timeout rather than being refused or
      # incurring DNS delay.
      started = monotonic_now
      assert_raises(Valkey::CannotConnectError) do
        ::Valkey.new(
          host: "192.0.2.1",
          port: 6379,
          connect_timeout: connect_timeout,
          reconnect_attempts: 1 # Should be zero however issue #117 blocks this.
        )
      end
      elapsed = monotonic_now - started

      max_allowed = connect_timeout * 2.5
      assert elapsed < max_allowed,
             "connect took #{elapsed.round(2)}s, expected < #{max_allowed}s " \
             "(connect_timeout not being respected)"
    end

    # should reject a new connection with a small connect timeout while the
    # server is blocked by a long-running command, yet allow one with a
    # generous timeout
    def test_connection_timeout_when_server_is_blocked
      skip("connection lifecycle tests only run on standalone mode") if cluster_mode?
      skip("DEBUG SLEEP is not enabled on this server") unless debug_sleep_available?

      blocker = _new_client
      sleep_seconds = 3
      blocker_thread = Thread.new do
        # DEBUG SLEEP blocks the (single-threaded) server for the full duration
        # even if this client's request times out first; the FFI command call
        # releases the GVL, so the main thread keeps running.
        blocker.send_command(Valkey::RequestType::CUSTOM_COMMAND, ["DEBUG", "SLEEP", sleep_seconds.to_s])
      rescue Valkey::BaseError
        nil # the assertions below are what matter
      end

      # Give the server a moment to enter the blocked state.
      sleep(0.5)

      # A short connection timeout must fail while the server is blocked.
      assert_raises(Valkey::CannotConnectError) do
        _new_client(connect_timeout: 0.1, reconnect_attempts: 1) # Should be zero however issue #117 blocks this.
      end

      # A generous connection timeout should still connect once the block clears.
      patient = _new_client(connect_timeout: 10.0)
      assert_equal "PONG", patient.ping
      patient.close
    ensure
      blocker_thread&.join
      blocker&.close
    end

    private

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Probes whether DEBUG SLEEP is permitted on the server (it requires
    # enable-debug-command). Uses the shared client and a zero-length sleep.
    def debug_sleep_available?
      r.send_command(Valkey::RequestType::CUSTOM_COMMAND, %w[DEBUG SLEEP 0])
      true
    rescue Valkey::CommandError
      false
    end
  end
end
