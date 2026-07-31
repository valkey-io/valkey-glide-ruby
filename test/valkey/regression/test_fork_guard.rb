# frozen_string_literal: true

require "test_helper"
require "timeout"

# Regression tests for the fork() guard.
#
# glide-core's tokio runtime is not fork-safe: any Valkey client created in
# the parent process crashes the child with SIGTRAP on first use. The
# Ruby-side guard raises Valkey::InheritedError instead, keeping the child's
# Ruby VM alive. See https://github.com/valkey-io/valkey-glide/issues/6672
# and https://github.com/valkey-io/valkey-glide-ruby/issues/210.
if Process.respond_to?(:fork)
  class TestForkGuard < Minitest::Test
    PORT = Integer(ENV["VALKEY_PORT"] || 8102)

    def test_inherited_client_raises_inherited_error_in_child
      parent = Valkey.new(host: "127.0.0.1", port: PORT)
      assert_equal "PONG", parent.ping

      status = nil
      Timeout.timeout(10) do
        pid = fork do
          # Rescue InheritedError → exit 0; any other exit path (crash, other
          # exception) will be caught by the parent's status check below.
          parent.ping
          exit 42 # should never reach here
        rescue Valkey::InheritedError
          exit 0
        rescue StandardError
          exit 43
        end
        _, status = Process.waitpid2(pid)
      end

      refute_nil status, "child status was not captured"
      # Child MUST NOT be killed by a signal — that's exactly the SIGTRAP
      # abort the guard exists to prevent.
      refute status.signaled?, "child was signaled (signal #{status.termsig}); guard failed to prevent abort"
      assert_equal 0, status.exitstatus, "child did not raise Valkey::InheritedError as expected"
    ensure
      parent&.close
    end

    def test_parent_client_still_works_after_fork
      parent = Valkey.new(host: "127.0.0.1", port: PORT)
      assert_equal "PONG", parent.ping

      Timeout.timeout(10) do
        pid = fork do
          # Child intentionally does nothing but exit cleanly. We just want
          # to prove the parent's client remains usable after fork().
          exit 0
        end
        Process.waitpid2(pid)
      end

      assert_equal "PONG", parent.ping
    ensure
      parent&.close
    end

    def test_child_can_create_its_own_client_after_fork
      # This is the correct pattern documented in README "Forking servers":
      # the parent process must never have created a client before fork(),
      # otherwise glide-core's tokio runtime state contaminates the child.
      # We spawn a fresh Ruby subprocess so no prior FFI usage bleeds in.
      lib = File.expand_path("../../../lib", __dir__)
      script = <<~RUBY
        $LOAD_PATH.unshift(#{lib.inspect})
        require "valkey"
        pid = fork do
          client = Valkey.new(host: "127.0.0.1", port: #{PORT})
          exit(client.ping == "PONG" ? 0 : 45)
        end
        _, status = Process.waitpid2(pid)
        exit(status.signaled? ? 46 : (status.exitstatus || 47))
      RUBY

      ok = nil
      Timeout.timeout(10) do
        ok = system(RbConfig.ruby, "-e", script)
      end

      assert ok, "post-fork Valkey.new pattern failed inside a fresh subprocess"
    end

    def test_inherited_error_message_references_upstream_issues
      parent = Valkey.new(host: "127.0.0.1", port: PORT)

      # Capture the error message from a forked child via a pipe. Doing the
      # assertion in-process would require the guard to fire in the parent,
      # which it can't — the parent IS @created_pid.
      reader, writer = IO.pipe

      Timeout.timeout(10) do
        pid = fork do
          reader.close
          parent.ping
        rescue Valkey::InheritedError => e
          writer.write(e.message)
          writer.close
          exit 0
        end
        writer.close
        message = reader.read
        Process.waitpid2(pid)
        # Message must reference at least one of the tracking issue numbers so
        # operators can find the upstream tracker.
        assert(message.include?("6672") || message.include?("210"),
               "expected InheritedError message to reference issue #6672 or #210, got: #{message.inspect}")
      end
    ensure
      reader&.close unless reader&.closed?
      parent&.close
    end
  end
end
