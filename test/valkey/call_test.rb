# frozen_string_literal: true

module ValkeyTests
  module Call
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

    def test_call_stringifies_integers_and_floats
      assert_equal "OK", r.call("SET", "call:num", 42)
      assert_equal "42", r.call("GET", "call:num")

      assert_equal "OK", r.call("SET", "call:float", 3.5)
      assert_equal "3.5", r.call("GET", "call:float")
    end

    def test_call_flattens_array_arguments
      r.del("call:list")

      assert_equal 3, r.call("LPUSH", "call:list", [1, 2, 3])
      assert_equal %w[3 2 1], r.call("LRANGE", "call:list", 0, -1)
    end

    def test_call_flattens_nested_array_arguments
      r.del("call:list2")

      assert_equal 3, r.call("LPUSH", "call:list2", [1, [2, 3]])
      assert_equal %w[3 2 1], r.call("LRANGE", "call:list2", 0, -1)
    end

    def test_call_flattens_hash_arguments
      r.del("call:hash")

      assert_equal "OK", r.call("HMSET", "call:hash", { "foo" => "1" })
      assert_equal "1", r.call("HGET", "call:hash", "foo")
    end

    def test_call_v_flattens_array_and_hash_arguments
      r.del("call:v:list")
      r.del("call:v:hash")

      assert_equal 3, r.call_v(["LPUSH", "call:v:list", [1, 2, 3]])
      assert_equal "OK", r.call_v(["HMSET", "call:v:hash", { "foo" => "1" }])
    end

    def test_call_kwargs_become_trailing_flags
      r.del("call:flags")

      assert_equal "OK", r.call("SET", "call:flags", "v", nx: true, ex: 60)
      assert_in_range 1..60, r.ttl("call:flags")

      # NX means "only set if not exists" — key already exists, so this is a no-op (nil reply)
      assert_nil r.call("SET", "call:flags", "v2", nx: true)
      assert_equal "v", r.call("GET", "call:flags")
    end

    def test_call_drops_falsy_and_nil_kwargs
      r.del("call:flags2")

      # nx: false and ex: nil should be dropped entirely, not stringified
      assert_equal "OK", r.call("SET", "call:flags2", "v", nx: false, ex: nil)
      assert_equal(-1, r.ttl("call:flags2"))
    end

    # The tests above exercise flattening/coercion indirectly, through server-visible
    # side effects (e.g. LPUSH's returned length, LRANGE's returned order) — they
    # confirm the server *received something equivalent*, not the exact argument
    # array `call`/`call_v` constructed. These stub `send_command` (same technique as
    # `capture_failover_args` in failover_commands_test.rb) to assert on the literal
    # flattened/coerced array before it ever reaches the network, independent of any
    # particular command's server-side semantics.

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

    # should apply the same flattening to call_v's single Array argument
    def test_call_v_arg_construction_flattens
      assert_equal %w[LPUSH list 1 2 3], capture_call_v_args(["LPUSH", "list", [1, 2, 3]])
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
