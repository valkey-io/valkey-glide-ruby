# frozen_string_literal: true

module Lint
  module ScriptingCommands
    def to_sha(script)
      r.script(:load, script)
    end

    # script commands

    def test_script_exists
      a = to_sha("return 1")
      b = a.succ

      r.invoke_script(a)

      assert_equal true, r.script(:exists, a)
      assert_equal false, r.script(:exists, b)
      assert_equal [true], r.script(:exists, [a])
      assert_equal [false], r.script(:exists, [b])
      assert_equal [true, false], r.script(:exists, [a, b])
    end

    def test_script_flush
      sha = to_sha("return 1")
      r.invoke_script(sha)
      assert r.script(:exists, sha)
      assert_equal "OK", r.script(:flush)
      assert !r.script(:exists, sha)
    end

    def test_script_kill
      assert_raises(Valkey::CommandError) { r.script_kill }
    end

    # eval tests

    def test_eval_basic
      result = r.eval("return 42")
      assert_equal 42, result

      result = r.eval("return 'hello'")
      assert_equal "hello", result
    end

    def test_eval_with_keys_and_args
      result = r.eval("return KEYS[1] .. ARGV[1]", keys: ["mykey"], args: ["myarg"])
      assert_equal "mykeymyarg", result
    end

    def test_eval_empty_script
      assert_raises(ArgumentError) { r.eval("") }
      assert_raises(ArgumentError) { r.eval(nil) }
    end

    def test_eval_empty_keys_and_args
      result = r.eval("return #KEYS + #ARGV", keys: [], args: [])
      assert_equal 0, result

      result = r.eval("return #KEYS + #ARGV")
      assert_equal 0, result
    end

    def test_eval_error_message_preservation
      error_script = "error('custom error message')"
      error = assert_raises(Valkey::CommandError) { r.eval(error_script) }
      assert_includes error.message.downcase, "custom error message"
    end

    # evalsha tests

    def test_evalsha_basic
      script = "return 42"
      sha = r.script_load(script)
      result = r.evalsha(sha)
      assert_equal 42, result
    end

    def test_evalsha_invalid_sha
      assert_raises(ArgumentError) { r.evalsha("invalid") }
      assert_raises(ArgumentError) { r.evalsha("") }
      assert_raises(ArgumentError) { r.evalsha("1234567890123456789012345678901234567890x") }
    end

    def test_evalsha_nonexistent_script
      valid_sha = "1234567890123456789012345678901234567890"
      assert_raises(Valkey::CommandError) { r.evalsha(valid_sha) }
    end

    def test_evalsha_empty_keys_and_args
      script = "return #KEYS + #ARGV"
      sha = r.script_load(script)

      result = r.evalsha(sha, keys: [], args: [])
      assert_equal 0, result

      result = r.evalsha(sha)
      assert_equal 0, result
    end

    def test_evalsha_error_message_preservation
      error_script = "error('evalsha custom error')"
      sha = r.script_load(error_script)
      error = assert_raises(Valkey::CommandError) { r.evalsha(sha) }
      assert_includes error.message.downcase, "evalsha custom error"
    end

    # eval/evalsha integration

    def test_integration_with_script_load
      scripts = [
        "return 42",
        "return 'hello'",
        "return {1, 2, 3}",
        "return KEYS[1] or 'default'",
        "return ARGV[1] or 'default'"
      ]

      scripts.each do |script|
        sha = r.script_load(script)
        assert_equal 40, sha.length
        assert sha.match?(/\A[a-fA-F0-9]{40}\z/)

        keys = ["testkey"]
        args = ["testarg"]

        evalsha_result = r.evalsha(sha, keys: keys, args: args)
        eval_result = r.eval(script, keys: keys, args: args)
        assert_equal eval_result, evalsha_result
      end
    end

    def test_script_cache_persistence
      script = "return math.random()"
      sha = r.script_load(script)

      5.times do
        result = r.evalsha(sha)
        assert result.is_a?(Integer)
        assert result.between?(0, 1)
      end
    end

    def test_eval_evalsha_parameter_type_conversion
      script = "return {type(KEYS[1]), type(ARGV[1]), type(ARGV[2]), type(ARGV[3])}"
      sha = r.script_load(script)

      keys = [123]
      args = [456, 78.9, true]

      eval_result = r.eval(script, keys: keys, args: args)
      evalsha_result = r.evalsha(sha, keys: keys, args: args)

      expected = %w[string string string string]
      assert_equal expected, eval_result
      assert_equal expected, evalsha_result
      assert_equal eval_result, evalsha_result
    end

    def test_large_parameter_arrays
      script = "return #KEYS + #ARGV"
      sha = r.script_load(script)

      large_keys = (1..50).map { |i| "key#{i}" }
      large_args = (1..50).map { |i| "arg#{i}" }

      eval_result = r.eval(script, keys: large_keys, args: large_args)
      evalsha_result = r.evalsha(sha, keys: large_keys, args: large_args)

      assert_equal 100, eval_result
      assert_equal 100, evalsha_result
      assert_equal eval_result, evalsha_result
    end

    # eval_ro tests

    def test_eval_ro_basic
      result = r.eval_ro("return 42")
      assert_equal 42, result
    end

    def test_eval_ro_with_keys_and_args
      r.set("mykey", "hello")
      result = r.eval_ro("return redis.call('get', KEYS[1])", keys: ["mykey"])
      assert_equal "hello", result
    end

    def test_eval_ro_empty_script
      assert_raises(ArgumentError) { r.eval_ro("") }
      assert_raises(ArgumentError) { r.eval_ro(nil) }
    end

    def test_eval_ro_consistency_with_eval
      script = "return 42"
      eval_result = r.eval(script)
      eval_ro_result = r.eval_ro(script)
      assert_equal eval_result, eval_ro_result
    end

    # evalsha_ro tests

    def test_evalsha_ro_basic
      script = "return 42"
      sha = r.script_load(script)
      result = r.evalsha_ro(sha)
      assert_equal 42, result
    end

    def test_evalsha_ro_with_keys
      r.set("mykey", "world")
      script = "return redis.call('get', KEYS[1])"
      sha = r.script_load(script)
      result = r.evalsha_ro(sha, keys: ["mykey"])
      assert_equal "world", result
    end

    def test_evalsha_ro_invalid_sha
      assert_raises(ArgumentError) { r.evalsha_ro("invalid") }
      assert_raises(ArgumentError) { r.evalsha_ro("") }
    end

    def test_evalsha_ro_nonexistent_script
      valid_sha = "1234567890123456789012345678901234567890"
      assert_raises(Valkey::CommandError) { r.evalsha_ro(valid_sha) }
    end

    def test_evalsha_ro_consistency_with_evalsha
      script = "return 'hello'"
      sha = r.script_load(script)
      evalsha_result = r.evalsha(sha)
      evalsha_ro_result = r.evalsha_ro(sha)
      assert_equal evalsha_result, evalsha_ro_result
    end

    # script_debug tests

    def test_script_debug
      skip("SCRIPT DEBUG requires a debugging client")

      assert_equal "OK", r.script_debug("YES")
      assert_equal "OK", r.script_debug("NO")
    end

    def test_script_debug_via_dispatcher
      skip("SCRIPT DEBUG requires a debugging client")

      assert_equal "OK", r.script(:debug, "YES")
      assert_equal "OK", r.script(:debug, "NO")
    end
  end
end
