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
#
# test_concurrent_close_releases_native_handle_once_traced moved to
# test/unit/connection_lifecycle_test.rb -- it never opens a real
# connection (Valkey.allocate + direct ivar sets), so it runs without a
# server.
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

    # should raise rather than segfault when a batch is issued after close.
    # `pipelined` and `multi` reach Bindings.batch, which used to receive the
    # nulled-out connection handle and crash the VM (issue #212).
    def test_closed_client_raises_on_pipelined
      skip("connection lifecycle tests only run on standalone mode") if cluster_mode?

      client = _new_client
      client.close

      error = assert_raises(Valkey::ConnectionError) { client.pipelined { |p| p.get("foo") } }
      assert_match(/the client is closed/, error.message)
    end

    # should raise rather than segfault when a transaction is issued after close
    # (the is_atomic batch path, issue #212)
    def test_closed_client_raises_on_multi
      skip("connection lifecycle tests only run on standalone mode") if cluster_mode?

      client = _new_client
      client.close

      error = assert_raises(Valkey::ConnectionError) { client.multi { |m| m.get("foo") } }
      assert_match(/the client is closed/, error.message)
    end

    # should raise rather than segfault when a script is evaluated after close.
    # `eval`/`evalsha` reach Bindings.invoke_script (issue #212).
    def test_closed_client_raises_on_eval
      skip("connection lifecycle tests only run on standalone mode") if cluster_mode?

      client = _new_client
      client.close

      error = assert_raises(Valkey::ConnectionError) { client.eval("return 1") }
      assert_match(/the client is closed/, error.message)
    end

    def test_closed_client_raises_on_evalsha
      skip("connection lifecycle tests only run on standalone mode") if cluster_mode?

      client = _new_client
      sha = client.script_load("return 1")
      client.close

      error = assert_raises(Valkey::ConnectionError) { client.evalsha(sha) }
      assert_match(/the client is closed/, error.message)
    end

    # invoke_script is public API, so it is worth covering directly rather than
    # only through eval/evalsha.
    def test_closed_client_raises_on_invoke_script
      skip("connection lifecycle tests only run on standalone mode") if cluster_mode?

      client = _new_client
      sha = client.script_load("return 1")
      client.close

      error = assert_raises(Valkey::ConnectionError) { client.invoke_script(sha) }
      assert_match(/the client is closed/, error.message)
    end

    # closing twice must free the native handle exactly once, not double-free,
    # and must leave the client cleanly closed rather than half torn down
    def test_close_is_idempotent
      skip("connection lifecycle tests only run on standalone mode") if cluster_mode?

      client = _new_client

      closed = []
      Valkey::Bindings.stub(:close_client, ->(conn) { closed << conn }) do
        client.close
        client.close
        client.close
      end

      assert_equal 1, closed.size, "close_client should be invoked exactly once across repeated close calls"
      refute_nil closed.first

      error = assert_raises(Valkey::ConnectionError) { client.get("foo") }
      assert_match(/the client is closed/, error.message)
    ensure
      # the stub intercepted the real free, so release the handle for real
      Valkey::Bindings.close_client(closed.first) if closed&.first
    end

    # closing from several threads at once must still free the handle exactly
    # once. `close` uses `Mutex#try_lock` so exactly one caller reaches
    # close_client while the rest short-circuit (issue #212, R3-10).
    def test_concurrent_close_frees_handle_once
      skip("connection lifecycle tests only run on standalone mode") if cluster_mode?

      client = _new_client

      closed = []
      mutex = Mutex.new # test-side aggregation only
      Valkey::Bindings.stub(:close_client, ->(conn) { mutex.synchronize { closed << conn } }) do
        8.times.map { Thread.new { client.close } }.each(&:join)
      end

      assert_equal 1, closed.size, "close_client should be invoked exactly once across concurrent close calls"
    ensure
      Valkey::Bindings.close_client(closed.first) if closed&.first
    end

    # a thread closing the client while another is mid-command must raise a
    # catchable ConnectionError, never segfault the VM. This is the TOCTOU half
    # of issue #212 (R3-10): the guard reads the handle into a local, so a
    # concurrent `close` cannot null the reference between check and native call.
    # Covers the batch path (`pipelined`) and the script path (`eval`), which
    # both crashed the process before the fix.
    def test_close_racing_in_flight_commands_does_not_crash
      skip("connection lifecycle tests only run on standalone mode") if cluster_mode?

      key = "lifecycle:race"

      [
        ->(c) { c.pipelined { |p| p.get(key) } },
        ->(c) { c.eval("return 1") },
        ->(c) { c.get(key) }
      ].each do |operation|
        client = _new_client
        client.set(key, "v")

        unexpected = nil
        worker = Thread.new do
          200.times { operation.call(client) }
        rescue Valkey::BaseError
          nil # expected once the client is closed mid-flight
        rescue StandardError => e
          unexpected = e
        end

        sleep 0.02
        client.close
        worker.join

        # reaching here at all means the VM survived; the fix's real assertion
        # is the absence of a segfault, which would take the whole suite down
        assert_nil unexpected, "racing close raised an unexpected error: #{unexpected.inspect}"
      end
    end

    # `close` must work from a signal-trap handler - `Signal.trap("TERM") { client.close }`
    # is the standard graceful-shutdown idiom, and Ruby forbids taking a lock in
    # trap context, so `close` must stay lock-free (issue #212).
    def test_close_works_in_trap_context
      skip("connection lifecycle tests only run on standalone mode") if cluster_mode?

      client = _new_client
      outcome = nil

      previous = Signal.trap("USR2") do
        client.close
        outcome = :closed
      rescue StandardError => e
        outcome = e
      end

      # signalling ourselves runs the handler before Process.kill returns
      Process.kill("USR2", Process.pid)

      assert_equal :closed, outcome, "close raised in trap context: #{outcome.inspect}"

      # and the client is left properly closed, not half torn down
      error = assert_raises(Valkey::ConnectionError) { client.get("foo") }
      assert_match(/the client is closed/, error.message)
    ensure
      # minitest runs the whole suite in one process and USR2's default
      # disposition terminates it, so the handler must not outlive this test
      Signal.trap("USR2", previous) if previous
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
