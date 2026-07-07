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
  end
end
