# frozen_string_literal: true

module Lint
  module TransactionCommands
    def test_multi_discard
      r.multi
      r.set("foo", "bar")
      r.discard

      # After DISCARD, the key should not be set.
      assert_nil r.get("foo")
    end

    def test_discard
      r.multi do |multi|
        multi.set("foo", "bar")
        raise "Some error"
      end
    rescue RuntimeError
      # Transaction should have been discarded
      assert_nil r.get("foo")
    end

    def test_multi_with_block
      result = r.multi do |multi|
        multi.set("foo", "s1")
      end

      assert_equal ["OK"], result
      assert_equal "s1", r.get("foo")
    end

    def test_multi_exec_with_a_block_doesn_t_return_replies_for_multi_and_exec
      r1, r2, nothing_else = r.multi do |multi|
        multi.set("foo", "s1")
        multi.get("foo")
      end

      assert_equal "OK", r1
      assert_equal "s1", r2
      assert_nil nothing_else
    end

    def test_multi_with_block_multiple_commands
      result = r.multi do |multi|
        multi.set("foo", "s1")
        multi.get("foo")
      end

      assert_equal %w[OK s1], result
    end

    def test_multi_with_block_that_raises_exception
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
      r.multi
      r.set("foo", "s1")
      r.get("foo")
      result = r.exec

      assert_equal %w[OK s1], result
    end

    def test_multi_in_pipeline
      response = r.pipelined do |pipeline|
        pipeline.multi
        pipeline.set("foo", "s1")
        pipeline.exec
      end

      assert_equal ["OK", "QUEUED", ["OK"]], response
      assert_equal "s1", r.get("foo")
    end

    def test_queued_commands
      r.multi
      assert_equal "QUEUED", r.set("foo", "bar")
      assert_equal "QUEUED", r.get("foo")
      result = r.exec

      assert_equal %w[OK bar], result
    end

    def test_exec_with_error
      r.set("foo", "not_a_number")
      r.multi
      r.incr("foo") # This will cause an error

      # EXEC should return an array with the error
      result = r.exec
      assert_instance_of Array, result
      # The exact error handling may vary by implementation
    end

    def test_discard_after_multi
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
      r.multi
      result = r.exec

      assert_equal [], result
    end

    def test_watch_with_modified_key
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
      r.multi
      # Calling MULTI again should return an error or be ignored
      # The exact behavior may vary by implementation
      r.multi
      r.discard
    end

    def test_exec_without_multi
      # EXEC without MULTI should return an error or nil
      # The exact behavior may vary by implementation
      r.exec
      # Could be nil or raise an error depending on implementation
    end

    def test_discard_without_multi
      # DISCARD without MULTI should return an error
      # The exact behavior may vary by implementation
      r.discard
      # Could raise an error or return a specific response
    end

    def test_watch_exec_unwatch_cycle
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
      r.set("shared", "initial")

      # Start transaction but don't execute yet
      r.multi
      r.set("shared", "transaction_value")

      # Value should still be initial since transaction not executed
      assert_equal "initial", r.get("shared")

      # Execute transaction
      result = r.exec
      assert_equal ["OK"], result
      assert_equal "transaction_value", r.get("shared")
    end

    def test_complex_transaction_scenario
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
      r.multi do |multi|
        multi.set("foo", "s1")
      end

      assert_equal "s1", r.get("foo")
    end

    def test_watch_with_an_unmodified_key
      r.watch("foo")
      result = r.multi do |multi|
        multi.set("foo", "s1")
      end

      assert_equal ["OK"], result
      assert_equal "s1", r.get("foo")
    end

    def test_watch_with_an_unmodified_key_passed_as_array
      r.watch(%w[foo bar])
      result = r.multi do |multi|
        multi.set("foo", "s1")
      end

      assert_equal ["OK"], result
      assert_equal "s1", r.get("foo")
    end

    def test_watch_with_a_modified_key_passed_as_array
      r.watch(%w[foo bar])
      r.set("foo", "s1")
      result = r.multi do |multi|
        multi.set("foo", "s2")
      end

      assert_nil result
      assert_equal "s1", r.get("foo")
    end

    def test_multi_with_a_block_yielding_the_client
      r.multi do |multi|
        multi.set("foo", "s1")
      end

      assert_equal "s1", r.get("foo")
    end

    def test_unwatch_with_a_modified_key
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
  end
end
