# frozen_string_literal: true

require "test_helper"

# Run directly, in its own process (see the "Run isolated fork tests" step in
# ci.yml):
#
#   bundle exec ruby -Itest -Ilib test/isolated/fork_no_parent_command_test.rb
#
# glide-core arms a process-global timeout watchdog on the first command issued
# anywhere in the process. This test's precondition is that no command has been
# issued yet, which no shared suite can offer -- inside one, hundreds of earlier
# tests have already armed it and this would silently assert the opposite of
# what it claims.
class TestForkWithoutParentCommand < Minitest::Test
  def test_child_can_use_a_fresh_client_when_the_parent_issued_no_command
    skip("fork() unavailable on #{RUBY_PLATFORM}") unless Helper::Fork.supported?

    # Connect but issue nothing, leaving the watchdog unarmed.
    parent = Valkey.new(host: "127.0.0.1", port: PORT, timeout: TIMEOUT)

    verdict = Helper::Fork.run do
      { ping: Valkey.new(host: "127.0.0.1", port: PORT, timeout: TIMEOUT).ping }
    end

    assert_equal :exited, verdict.outcome, verdict.describe
    assert_equal 0, verdict.exitstatus, verdict.describe
    assert_equal "PONG", verdict.value[:ping]
  ensure
    parent&.close
  end
end
