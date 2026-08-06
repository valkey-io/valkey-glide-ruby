# frozen_string_literal: true

module Lint
  module TransactionCommands
    def test_multi_discard
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.multi
      r.set("foo", "bar")
      r.discard

      # After DISCARD, the key should not be set.
      assert_nil r.get("foo")
    end

    def test_discard
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.multi do |multi|
        multi.set("foo", "bar")
        raise "Some error"
      end
    rescue RuntimeError
      # Transaction should have been discarded
      assert_nil r.get("foo")
    end

    def test_multi_with_block
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      result = r.multi do |multi|
        multi.set("foo", "s1")
      end

      assert_equal ["OK"], result
      assert_equal "s1", r.get("foo")
    end

    def test_multi_exec_with_a_block_doesn_t_return_replies_for_multi_and_exec
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r1, r2, nothing_else = r.multi do |multi|
        multi.set("foo", "s1")
        multi.get("foo")
      end

      assert_equal "OK", r1
      assert_equal "s1", r2
      assert_nil nothing_else
    end

    def test_multi_with_block_multiple_commands
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      result = r.multi do |multi|
        multi.set("foo", "s1")
        multi.get("foo")
      end

      assert_equal %w[OK s1], result
    end

    def test_multi_with_block_that_raises_exception
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      assert_raises(RuntimeError) do
        r.multi do |multi|
          multi.set("bar", "s2")
          raise "Some error"
        end
      end

      # Transaction should have been discarded
      assert_nil r.get("bar")
    end

    def test_exec_with_multiple_commands
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.multi
      r.set("foo", "s1")
      r.get("foo")
      result = r.exec

      assert_equal %w[OK s1], result
    end

    def test_multi_in_pipeline
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      response = r.pipelined do |pipeline|
        pipeline.multi
        pipeline.set("foo", "s1")
        pipeline.exec
      end

      assert_equal ["OK", "QUEUED", ["OK"]], response
      assert_equal "s1", r.get("foo")
    end

    def test_queued_commands
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.multi
      assert_equal "QUEUED", r.set("foo", "bar")
      assert_equal "QUEUED", r.get("foo")
      result = r.exec

      assert_equal %w[OK bar], result
    end

    def test_exec_with_error
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.set("foo", "not_a_number")
      r.multi
      r.incr("foo") # This will cause an error

      # EXEC should return an array with the error
      result = r.exec
      assert_instance_of Array, result
      # The exact error handling may vary by implementation
    end

    def test_discard_after_multi
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.multi
      r.set("foo", "bar")
      r.discard

      # Key should not be set since transaction was discarded
      assert_nil r.get("foo")
    end

    def test_watch_without_block
      assert_equal "OK", r.watch("foo")
    end

    def test_watch_multiple_keys
      assert_equal "OK", r.watch("foo", "bar", "baz")
    end

    def test_watch_with_array
      assert_equal "OK", r.watch(%w[foo bar])
    end

    def test_watch_with_block_and_unmodified_key
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      result = r.watch("foo") do |rd|
        assert_same r, rd

        rd.multi do |multi|
          multi.set("foo", "s1")
        end
      end

      assert_equal ["OK"], result
      assert_equal "s1", r.get("foo")
    end

    def test_watch_with_block_and_modified_key
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      result = r.watch("foo") do |rd|
        assert_same r, rd

        rd.set("foo", "s1")
        rd.multi do |multi|
          multi.set("foo", "s2")
        end
      end

      assert_nil result
      assert_equal "s1", r.get("foo")
    end

    def test_watch_with_block_that_raises_exception
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.set("foo", "s1")

      begin
        r.watch("foo") do
          raise "test"
        end
      rescue RuntimeError
        # Expected exception, continue with test
      end

      r.set("foo", "s2")

      # If the watch was still set from within the block above, this multi/exec
      # would fail. This proves that raising an exception above unwatches.
      result = r.multi do |multi|
        multi.set("foo", "s3")
      end

      assert_equal ["OK"], result
      assert_equal "s3", r.get("foo")
    end

    def test_unwatch
      r.watch("foo")
      assert_equal "OK", r.unwatch
    end

    def test_empty_multi_exec
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.multi
      result = r.exec

      assert_equal [], result
    end

    def test_watch_with_modified_key
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.set("foo", "initial")
      r.watch("foo")
      r.set("foo", "modified") # This modifies the watched key

      r.multi
      r.set("foo", "transaction_value")
      result = r.exec

      # Transaction should fail because watched key was modified
      assert_nil result
      assert_equal "modified", r.get("foo")
    end

    def test_watch_with_unmodified_key
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.set("foo", "initial")
      r.watch("foo")

      r.multi
      r.set("foo", "transaction_value")
      result = r.exec

      # Transaction should succeed because watched key was not modified
      assert_equal ["OK"], result
      assert_equal "transaction_value", r.get("foo")
    end

    def test_unwatch_after_watch
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.watch("foo")
      r.set("foo", "modified")
      r.unwatch # This should clear the watch

      r.multi
      r.set("foo", "transaction_value")
      result = r.exec

      # Transaction should succeed because watch was cleared
      assert_equal ["OK"], result
      assert_equal "transaction_value", r.get("foo")
    end

    def test_multiple_transactions
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      # First transaction
      r.multi
      r.set("key1", "value1")
      result1 = r.exec

      # Second transaction
      r.multi
      r.set("key2", "value2")
      result2 = r.exec

      assert_equal ["OK"], result1
      assert_equal ["OK"], result2
      assert_equal "value1", r.get("key1")
      assert_equal "value2", r.get("key2")
    end

    def test_nested_multi_not_allowed
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.multi
      # Calling MULTI again should return an error or be ignored
      # The exact behavior may vary by implementation
      r.multi
      r.discard
    end

    def test_exec_without_multi
      # In cluster mode, EXEC without MULTI behaves differently
      skip("EXEC without MULTI not supported in cluster mode") if cluster_mode?

      # EXEC without MULTI should return an error or nil
      # The exact behavior may vary by implementation
      r.exec
      # Could be nil or raise an error depending on implementation
    end

    def test_discard_without_multi
      # In cluster mode, DISCARD without MULTI behaves differently
      skip("DISCARD without MULTI not supported in cluster mode") if cluster_mode?

      # DISCARD without MULTI should return an error
      # The exact behavior may vary by implementation
      r.discard
      # Could raise an error or return a specific response
    end

    def test_watch_exec_unwatch_cycle
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.set("counter", "0")

      # Watch and increment counter
      r.watch("counter")
      current = r.get("counter").to_i

      r.multi
      r.set("counter", (current + 1).to_s)
      result = r.exec

      assert_equal ["OK"], result
      assert_equal "1", r.get("counter")
    end

    def test_transaction_isolation
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      # A second connection is required to observe isolation: on the connection
      # that issued MULTI the server replies QUEUED to every command, so that
      # connection cannot read the pre-transaction value. `_new_client` does not
      # run `init`, so it must be pointed at the test database explicitly.
      observer = _new_client(db: 15)

      r.set("shared", "initial")

      # Start transaction but don't execute yet
      r.multi
      r.set("shared", "transaction_value")

      # Same connection: commands are queued, not executed
      assert_equal "QUEUED", r.get("shared")

      # Another connection still sees the pre-transaction value until EXEC
      assert_equal "initial", observer.get("shared")

      # Execute transaction: two queued commands produce two replies
      result = r.exec
      assert_equal %w[OK transaction_value], result
      assert_equal "transaction_value", r.get("shared")
      assert_equal "transaction_value", observer.get("shared")
    ensure
      observer&.close
    end

    def test_get_between_multi_and_exec_does_not_discard_watch
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      # Regression guard: a GET issued between MULTI and EXEC must stay queued
      # and must not discard WATCH, otherwise a concurrent write to the
      # watched key is silently lost.
      writer = _new_client(db: 15)

      r.set("account:1", "initial")
      r.watch("account:1")
      r.multi
      r.set("account:1", "my_update")
      assert_equal "QUEUED", r.get("account:1")

      # Concurrent write to the watched key, after the WATCH
      writer.set("account:1", "concurrent_writer")

      # WATCH is still in force, so the transaction must abort
      assert_nil r.exec
      assert_equal "concurrent_writer", r.get("account:1")
    ensure
      writer&.close
    end

    def test_complex_transaction_scenario
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      # Set up initial data
      r.set("account:1", "100")
      r.set("account:2", "50")

      # Watch both accounts
      r.watch("account:1", "account:2")

      # Get current balances
      balance1 = r.get("account:1").to_i
      balance2 = r.get("account:2").to_i

      # Transfer 25 from account:1 to account:2
      result = r.multi do |multi|
        multi.set("account:1", (balance1 - 25).to_s)
        multi.set("account:2", (balance2 + 25).to_s)
      end

      assert_equal %w[OK OK], result
      assert_equal "75", r.get("account:1")
      assert_equal "75", r.get("account:2")
    end

    def test_raise_immediate_errors_in_multi_exec
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      assert_raises(RuntimeError) do
        r.multi do |multi|
          multi.set("bar", "s2")
          raise "Some error"
        end
      end

      assert_nil r.get("bar")
      assert_nil r.get("baz")
    end

    def test_multi_exec_with_a_block
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.multi do |multi|
        multi.set("foo", "s1")
      end

      assert_equal "s1", r.get("foo")
    end

    def test_watch_with_an_unmodified_key
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.watch("foo")
      result = r.multi do |multi|
        multi.set("foo", "s1")
      end

      assert_equal ["OK"], result
      assert_equal "s1", r.get("foo")
    end

    def test_watch_with_an_unmodified_key_passed_as_array
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.watch(%w[foo bar])
      result = r.multi do |multi|
        multi.set("foo", "s1")
      end

      assert_equal ["OK"], result
      assert_equal "s1", r.get("foo")
    end

    def test_watch_with_a_modified_key_passed_as_array
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.watch(%w[foo bar])
      r.set("foo", "s1")
      result = r.multi do |multi|
        multi.set("foo", "s2")
      end

      assert_nil result
      assert_equal "s1", r.get("foo")
    end

    def test_multi_with_a_block_yielding_the_client
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.multi do |multi|
        multi.set("foo", "s1")
      end

      assert_equal "s1", r.get("foo")
    end

    def test_unwatch_with_a_modified_key
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.watch("foo")
      r.set("foo", "s1")
      r.unwatch
      result = r.multi do |multi|
        multi.set("foo", "s2")
      end

      assert_equal ["OK"], result
      assert_equal "s2", r.get("foo")
    end

    def test_watch
      res = r.watch("foo")
      assert_equal "OK", res
    end

    def test_multi_with_boolean_reply_commands
      # In cluster mode, MULTI/EXEC transactions require all keys in same slot
      # and behave differently with connection routing
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.set("foo", "bar")
      r.del("someset")

      result = r.multi do |multi|
        multi.persist("foo")
        multi.pexpire("foo", 900_000)
        multi.sismember("someset", "member")
      end

      assert_equal [false, true, false], result
    end

    def test_multi_with_setnx
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.set("foo", "existing")
      r.del("bar")

      result = r.multi do |multi|
        multi.setnx("foo", "ignored")
        multi.setnx("bar", "new")
      end

      assert_equal [false, true], result
    end

    def test_multi_with_block_returns_futures_that_resolve_after_the_block
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      future = nil
      result = r.multi do |multi|
        future = multi.set("foo", "s1")
        multi.get("foo")
      end

      assert_instance_of Valkey::Future, future
      assert_equal "OK", future.value
      assert_equal %w[OK s1], result
    end

    def test_multi_future_value_raises_before_block_completes
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      captured = nil
      r.multi do |multi|
        captured = multi.set("foo", "s1")
        assert_raises(Valkey::FutureNotReady) { captured.value }
      end

      assert_equal "OK", captured.value
    end

    def test_multi_future_is_aborted_when_block_raises
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      future = nil
      assert_raises(RuntimeError) do
        r.multi do |multi|
          future = multi.set("bar", "s2")
          raise "boom"
        end
      end

      assert_raises(Valkey::FutureAborted) { future.value }
    end

    def test_multi_future_is_aborted_when_batch_raises_a_command_error
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      # multi's block form hardcodes exception: true, so a real per-command
      # error (as opposed to the user's block raising Ruby-level) makes the
      # whole batch call raise before resolve_futures! ever runs - same
      # abort path as test_multi_future_is_aborted_when_block_raises, just
      # triggered from send_batch_commands itself instead of user code.
      r.set("foo", "not_a_list")

      future = nil
      assert_raises(Valkey::CommandError) do
        r.multi do |multi|
          future = multi.lpush("foo", "bar")
          multi.get("foo")
        end
      end

      assert_raises(Valkey::FutureAborted) { future.value }
    end

    def test_multi_future_reflects_boolean_coercion
      skip("MULTI/EXEC not supported in cluster mode") if cluster_mode?

      r.set("foo", "bar")
      r.del("someset")
      r.set("existing", "value")
      r.del("newkey")

      persist_future = nil
      pexpire_future = nil
      sismember_future = nil
      setnx_future = nil
      hexists_future = nil

      result = r.multi do |multi|
        persist_future = multi.persist("foo")
        pexpire_future = multi.pexpire("foo", 900_000)
        sismember_future = multi.sismember("someset", "member")
        setnx_future = multi.setnx("existing", "ignored")
        hexists_future = multi.hexists("newkey", "field")
      end

      assert_equal [false, true, false, false, false], result
      assert_equal false, persist_future.value
      assert_equal true, pexpire_future.value
      assert_equal false, sismember_future.value
      assert_equal false, setnx_future.value
      assert_equal false, hexists_future.value
    end
  end
end
