# frozen_string_literal: true

require "timeout"

# Integration test for the standalone FAILOVER command.
# NOTE: FAILOVER is a standalone-only command.
module ValkeyTests
  module FailoverCommands
    FAILOVER_TIMEOUT_MS = 10_000

    # Wall-clock backstop, above the wait_for_role? budget (60 * 0.5s = 30s).
    FAILOVER_TEST_DEADLINE = 45

    # should return "OK" and flip the connected primary's role to slave once
    # the coordinated failover to its replica completes.
    def test_failover_promotes_replica_and_returns_ok
      with_standalone_replica do |primary|
        Timeout.timeout(FAILOVER_TEST_DEADLINE) do
          assert_equal "master", primary.info("replication")["role"]

          # FAILOVER's TIMEOUT bounds the wait server-side; without it the wait is
          # "infinite" and the blocking command never returns. See
          # https://valkey.io/commands/failover/
          assert_equal "OK", primary.failover(timeout: FAILOVER_TIMEOUT_MS)

          assert wait_for_role?(primary, "slave"),
                 "timed out waiting for the primary to become a replica (role:slave)"
        end
      end
    rescue Timeout::Error
      flunk("failover did not complete within #{FAILOVER_TEST_DEADLINE}s " \
            "(client likely hanged during the role transition)")
    end

    # should raise a error when ABORT is requested but no failover is
    # currently in progress
    def test_failover_abort_with_no_failover_in_progress_raises
      assert_raises(Valkey::CommandError) { r.failover(abort: true) }
    end

    # should send "ABORT" only
    def test_failover_abort_sends_abort_only
      assert_equal ["ABORT"], capture_failover_args(abort: true, timeout: 5000)
    end

    # should not send "FORCE" unless a TO target is supplied
    def test_failover_force_without_target_omits_force
      assert_equal [], capture_failover_args(force: true)
    end

    # should build "TO host port FORCE TIMEOUT ms" in order for a full request
    def test_failover_builds_full_arg_list_in_order
      args = capture_failover_args(to: "127.0.0.1 6380", force: true, timeout: 5000)
      assert_equal ["TO", "127.0.0.1", "6380", "FORCE", "TIMEOUT", "5000"], args
    end

    private

    # Replace the send_command method used by failover() with a stub which captures the arguments and returns "OK".
    # This allows us to see the arguments passed to the failover command without actually executing it.
    def capture_failover_args(**options)
      captured = nil
      stub = lambda do |_request_type, args = [], &_block|
        captured = args
        "OK"
      end
      r.stub(:send_command, stub) { r.failover(**options) }
      captured
    end

    # Start a standalone primary with one replica and yields a
    # client connected to the primary. Cleans up afterward.
    def with_standalone_replica
      cluster = Valkey::TestCluster.new(
        cluster_mode: false,
        shard_count: 1,
        replica_count: 1
      )
      primary_addr = cluster.addresses.first
      client = Valkey.new(host: primary_addr[:host], port: primary_addr[:port], timeout: 5.0)
      yield(client)
    rescue Valkey::TestCluster::PythonNotFoundError, Valkey::TestCluster::ScriptNotFoundError => e
      skip("requires python3 + valkey-glide submodule for replica setup: #{e.message}")
    ensure
      client&.close
      cluster&.close
    end

    # Polls INFO REPLICATION until role matches (or times out).
    def wait_for_role?(client, role, attempts: 60, interval: 0.5)
      attempts.times do
        return true if client.info("replication")["role"] == role

        sleep(interval)
      end
      false
    end
  end
end
