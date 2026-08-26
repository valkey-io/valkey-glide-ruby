# frozen_string_literal: true

module ValkeyTests
  module Call
    # E2E: confirms call/call_v actually reach the server and the raw reply comes
    # back untyped. Argument-construction correctness (flattening order, flag
    # emission, coercion) is covered by the stub-based unit tests in
    # test/unit/commands/generic_commands_test.rb — these only need to prove the
    # whole pipeline (construct -> dispatch -> reply) works.

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
    # flattening/flag-construction cases themselves are unit-tested in
    # test/unit/commands/generic_commands_test.rb.
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
  end
end
