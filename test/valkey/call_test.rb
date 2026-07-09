# frozen_string_literal: true

module ValkeyTests
  module Call
    # E2E: confirms call/call_v actually reach the server and the raw reply comes
    # back untyped. Argument-construction correctness (flattening order, flag
    # emission, coercion) is covered by the stub-based unit tests below — these
    # only need to prove the whole pipeline (construct -> dispatch -> reply) works.

    def test_call_round_trip
      assert_equal "OK", r.call("SET", "call:key", "value")
      assert_equal "value", r.call("GET", "call:key")
    end

    def test_call_v_round_trip
      r.call("SET", "call:v:key1", "v1")
      r.call("SET", "call:v:key2", "v2")

      assert_equal %w[v1 v2], r.call_v(["MGET", "call:v:key1", "call:v:key2"])
    end

    def test_call_raises_command_error_for_unknown_command
      assert_raises(Valkey::CommandError) do
        r.call("NOTACOMMAND", "foo")
      end
    end

    def test_call_v_raises_command_error_for_unknown_command
      assert_raises(Valkey::CommandError) do
        r.call_v(%w[NOTACOMMAND foo])
      end
    end

    # should apply flattened Array/Hash args and kwargs-derived flags correctly
    # end-to-end (server-visible effects: 3-element list, hash field set, TTL from
    # a flag) in a single pass through the real dispatch path — the granular
    # flattening/flag-construction cases themselves are unit-tested below.
    def test_call_end_to_end_with_flattening_and_flags
      r.del("call:e2e:list", "call:e2e:hash")

      assert_equal 3, r.call("LPUSH", "call:e2e:list", [1, 2, 3])
      assert_equal %w[3 2 1], r.call("LRANGE", "call:e2e:list", 0, -1)

      assert_equal "OK", r.call("HMSET", "call:e2e:hash", { "foo" => "1" })
      assert_equal "1", r.call("HGET", "call:e2e:hash", "foo")

      assert_equal "OK", r.call("SET", "call:e2e:flagged", "v", nx: true, ex: 60)
      assert_in_range 1..60, r.ttl("call:e2e:flagged")

      # NX means "only set if not exists" — key already exists, so this is a no-op (nil reply)
      assert_nil r.call("SET", "call:e2e:flagged", "v2", nx: true)
      assert_equal "v", r.call("GET", "call:e2e:flagged")
    end

    # should apply the same Array/Hash flattening end-to-end via call_v's
    # single-Array argument (mirrors test_call_end_to_end_with_flattening_and_flags
    # for call — no kwargs/flags case here, since call_v doesn't take any).
    def test_call_v_end_to_end_with_flattening
      r.del("call:v:e2e:list", "call:v:e2e:hash")

      assert_equal 3, r.call_v(["LPUSH", "call:v:e2e:list", [1, 2, 3]])
      assert_equal %w[3 2 1], r.call_v(["LRANGE", "call:v:e2e:list", 0, -1])

      assert_equal "OK", r.call_v(["HMSET", "call:v:e2e:hash", { "foo" => "1" }])
      assert_equal "1", r.call_v(["HGET", "call:v:e2e:hash", "foo"])
    end

    # Everything below stubs `send_command` (same technique as `capture_failover_args`
    # in failover_commands_test.rb) to assert on the literal flattened/coerced
    # argument array before it ever reaches the network — independent of any
    # particular command's server-side semantics. This is where flattening/flag
    # correctness is actually verified; the E2E tests above just prove the pipeline
    # composes.

    # should pass args through unchanged when they are already flat strings
    def test_call_arg_construction_passthrough
      assert_equal %w[SET k v], capture_call_args("SET", "k", "v")
    end

    # should stringify Integer/Float args without flattening them
    def test_call_arg_construction_stringifies_integers_and_floats
      assert_equal %w[SET k 42], capture_call_args("SET", "k", 42)
      assert_equal %w[SET k 3.5], capture_call_args("SET", "k", 3.5)
    end

    # should flatten a single Array arg into its own separate elements, in order
    def test_call_arg_construction_flattens_array
      assert_equal %w[LPUSH list 1 2 3], capture_call_args("LPUSH", "list", [1, 2, 3])
    end

    # should recursively flatten nested Arrays, not just one level deep
    def test_call_arg_construction_flattens_nested_array
      assert_equal %w[LPUSH list 1 2 3 4], capture_call_args("LPUSH", "list", [1, [2, [3, 4]]])
    end

    # should flatten a Hash arg to alternating key/value strings, preserving pair order
    def test_call_arg_construction_flattens_hash
      assert_equal %w[HMSET hash foo 1 bar 2], capture_call_args("HMSET", "hash", { "foo" => 1, "bar" => 2 })
    end

    # should flatten a Hash whose values are Arrays (key preserved, value flattened)
    def test_call_arg_construction_flattens_hash_with_array_values
      assert_equal %w[CMD k foo 1 2], capture_call_args("CMD", "k", { "foo" => [1, 2] })
    end

    # should apply the same flattening to call_v's single Array argument,
    # including a Hash value that is itself an Array (mirrors
    # test_call_arg_construction_flattens_hash_with_array_values for call)
    def test_call_v_arg_construction_flattens
      assert_equal %w[LPUSH list 1 2 3], capture_call_v_args(["LPUSH", "list", [1, 2, 3]])
      assert_equal %w[CMD k foo 1 2], capture_call_v_args(["CMD", "k", { "foo" => [1, 2] }])
    end

    # should append upcased flag names for truthy boolean kwargs, in the order given
    def test_call_arg_construction_boolean_flags
      assert_equal %w[SET k v NX], capture_call_args("SET", "k", "v", nx: true)
    end

    # should append both the upcased flag name and its stringified value for
    # non-boolean truthy kwargs
    def test_call_arg_construction_value_flags
      assert_equal %w[SET k v EX 60], capture_call_args("SET", "k", "v", ex: 60)
    end

    # should drop false-valued and nil-valued kwargs entirely, not stringify them
    def test_call_arg_construction_drops_falsy_and_nil_flags
      assert_equal %w[SET k v], capture_call_args("SET", "k", "v", nx: false, ex: nil)
    end

    # should combine positional flattening and trailing flags in a single call,
    # flags always appended after all positional (including flattened) args
    def test_call_arg_construction_combines_flattening_and_flags
      assert_equal %w[SET k v NX EX 60], capture_call_args("SET", "k", "v", nx: true, ex: 60)
    end

    private

    # Replaces send_command with a stub that captures the args call() built, without
    # dispatching to the server. Mirrors capture_failover_args in
    # failover_commands_test.rb.
    def capture_call_args(*args, **kwargs)
      captured = nil
      stub = lambda do |_request_type, sent_args = [], &_block|
        captured = sent_args
        "OK"
      end
      r.stub(:send_command, stub) { r.call(*args, **kwargs) }
      captured
    end

    def capture_call_v_args(args)
      captured = nil
      stub = lambda do |_request_type, sent_args = [], &_block|
        captured = sent_args
        "OK"
      end
      r.stub(:send_command, stub) { r.call_v(args) }
      captured
    end
  end
end
