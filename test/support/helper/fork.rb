# frozen_string_literal: true

# Runs a block in a forked child and reports what happened to it.
#
# An exit code alone cannot tell a raised exception apart from a native crash or
# a hang, and those are the outcomes these tests exist to distinguish. So
# `Fork.run` returns a Verdict carrying `outcome` (:exited / :signaled / :hung),
# the child's exit status, and the block's return value, plus `describe` for
# failure messages that name the signal instead of printing a bare number.
#
# CRITICAL — do not replace the exit! below with exit.
# test/support/test_cluster.rb:39 registers an ObjectSpace finalizer that runs
# `cluster_manager.py stop`. A forked child inherits the TestCluster object, so a
# plain `exit` would tear down the server the parent test is still using.
module Helper
  module Fork
    # Bounded so a hang fails one test instead of wedging the suite.
    DEFAULT_TIMEOUT = Float(ENV["FORK_TEST_TIMEOUT"] || 20.0)

    POLL_INTERVAL = 0.02

    Verdict = Struct.new(:outcome, :exitstatus, :termsig, :value, :error, :timeout,
                         keyword_init: true) do
      def describe
        case outcome
        when :signaled then "child killed by #{signal_name} (termsig #{termsig})"
        when :hung then "child did not exit within #{timeout}s and was SIGKILLed"
        else "child exited with status #{exitstatus.inspect}#{error && " after #{error}"}"
        end
      end

      def signal_name
        name = termsig && ::Signal.signame(termsig)
        name ? "SIG#{name}" : "signal"
      end
    end

    class << self
      def supported?
        ::Process.respond_to?(:fork) && !RUBY_PLATFORM.match?(/mswin|mingw|java/)
      end

      def run(timeout: DEFAULT_TIMEOUT, &block)
        reader, writer = IO.pipe

        pid = ::Process.fork do
          reader.close
          run_child(writer, &block)
        end

        writer.close
        # Drained on a thread so a payload larger than the pipe buffer cannot
        # deadlock the child against the parent's waitpid.
        payload = Thread.new { reader.binmode.read }
        outcome, status = wait(pid, timeout)

        build_verdict(outcome, status, load_payload(payload), timeout)
      ensure
        [writer, reader].each { |io| io.close if io && !io.closed? }
      end

      private

      def run_child(writer)
        status = 0
        payload =
          begin
            { value: yield }
          rescue Exception => e # rubocop:disable Lint/RescueException
            # Must catch everything, including Minitest::Assertion, or a failure
            # inside the child reaches the parent as a bare exit code.
            status = 1
            { error: "#{e.class}: #{e.message}" }
          end

        begin
          writer.binmode
          writer.write(Marshal.dump(payload))
          writer.close
        rescue StandardError
          nil # a broken pipe must not change the child's exit status
        end

        ::Process.exit!(status) # see the file header
      end

      def wait(pid, timeout)
        deadline = monotonic + timeout

        loop do
          reaped, status = ::Process.wait2(pid, ::Process::WNOHANG)
          return [status.signaled? ? :signaled : :exited, status] if reaped
          break if monotonic >= deadline

          sleep POLL_INTERVAL
        end

        kill(pid)
        [:hung, nil]
      rescue Errno::ECHILD
        [:exited, nil]
      end

      def kill(pid)
        ::Process.kill("KILL", pid)
        ::Process.wait2(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end

      def load_payload(thread)
        raw = thread.value
        return {} if raw.nil? || raw.empty?

        Marshal.load(raw) # rubocop:disable Security/MarshalLoad
      rescue StandardError
        {}
      end

      def build_verdict(outcome, status, payload, timeout)
        Verdict.new(
          outcome: outcome,
          exitstatus: status&.exitstatus,
          termsig: status&.termsig,
          value: payload[:value],
          error: payload[:error],
          timeout: timeout
        )
      end

      def monotonic
        ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      end
    end
  end
end
