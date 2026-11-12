# frozen_string_literal: true

# Fork-safety integration tests (issue #255).
#
# Before the PID guard a child that touched an inherited handle died by signal
# rather than raising: SIGTRAP on a command, SIGABRT on close. Assertions go
# through Helper::Fork::Verdict so a crash or a hang cannot read as an ordinary
# failure.
module ValkeyTests
  module ForkSafety
    FORK_KEY = "fork-safety:key"

    INHERITED_MESSAGE = "Cannot use a client created before fork(). " \
                        "Create a new client in the child process."

    def test_fork_child_proc_with_old_client
      skip("fork() unavailable on #{RUBY_PLATFORM}") unless Helper::Fork.supported?

      client = _new_client
      # Arms glide-core's process-global watchdog; without this the child has
      # nothing stale to touch.
      assert_equal "PONG", client.ping
      assert_equal "OK", client.set(FORK_KEY, "before-fork")

      verdict = Helper::Fork.run do
        error = begin
          client.get(FORK_KEY)
          nil
        rescue Valkey::InheritedError => e
          "#{e.class}: #{e.message}"
        end
        client.close # used to abort the child with SIGABRT
        { error: error, closed: true }
      end

      assert_equal :exited, verdict.outcome, verdict.describe
      assert_equal 0, verdict.exitstatus, verdict.describe
      assert_equal "Valkey::InheritedError: #{INHERITED_MESSAGE}", verdict.value[:error]
      assert verdict.value[:closed], "child did not finish close"

      assert_equal "before-fork", client.get(FORK_KEY)
      assert_equal "OK", client.set(FORK_KEY, "after-fork")
      assert_equal "after-fork", client.get(FORK_KEY)
    ensure
      client&.del(FORK_KEY)
      client&.close
    end

    # The parent uses a client before forking, which arms glide-core's global
    # timeout watchdog. Without valkey-glide#7569, which rebuilds it in the
    # child, the child's new client is killed by SIGTRAP on macOS.
    def test_fork_child_proc_with_new_client
      client = _new_client
      assert_equal "PONG", client.ping
      assert_equal "OK", client.set(FORK_KEY, "before-fork")

      verdict = Helper::Fork.run { { ping: _new_client.ping } }

      assert_equal :exited, verdict.outcome, verdict.describe
      assert_equal 0, verdict.exitstatus, verdict.describe
      assert_equal "PONG", verdict.value[:ping]

      assert_equal "before-fork", client.get(FORK_KEY)
    ensure
      client&.del(FORK_KEY)
      client&.close
    end
  end
end
