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
      target_version "7.0" do
        result = r.eval_ro("return 42")
        assert_equal 42, result
      end
    end

    def test_eval_ro_with_keys_and_args
      target_version "7.0" do
        r.set("mykey", "hello")
        result = r.eval_ro("return redis.call('get', KEYS[1])", keys: ["mykey"])
        assert_equal "hello", result
      end
    end

    def test_eval_ro_empty_script
      assert_raises(ArgumentError) { r.eval_ro("") }
      assert_raises(ArgumentError) { r.eval_ro(nil) }
    end

    def test_eval_ro_consistency_with_eval
      target_version "7.0" do
        script = "return 42"
        eval_result = r.eval(script)
        eval_ro_result = r.eval_ro(script)
        assert_equal eval_result, eval_ro_result
      end
    end

    # evalsha_ro tests

    def test_evalsha_ro_basic
      target_version "7.0" do
        script = "return 42"
        sha = r.script_load(script)
        result = r.evalsha_ro(sha)
        assert_equal 42, result
      end
    end

    def test_evalsha_ro_with_keys
      target_version "7.0" do
        r.set("mykey", "world")
        script = "return redis.call('get', KEYS[1])"
        sha = r.script_load(script)
        result = r.evalsha_ro(sha, keys: ["mykey"])
        assert_equal "world", result
      end
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
      target_version "7.0" do
        script = "return 'hello'"
        sha = r.script_load(script)
        evalsha_result = r.evalsha(sha)
        evalsha_ro_result = r.evalsha_ro(sha)
        assert_equal evalsha_result, evalsha_ro_result
      end
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

    # integer key-count form - eval(script, numkeys, *keys, *args)
    #
    # This is the form used by the Valkey documentation and valkey-cli. It used
    # to be misparsed: the count became KEYS[1], the real key shifted into
    # ARGV[1], and any remaining arguments were dropped, all without raising.

    def test_eval_with_integer_numkeys
      assert_equal %w[mykey myarg],
                   r.eval("return {KEYS[1], ARGV[1]}", 1, "mykey", "myarg")
    end

    def test_eval_with_integer_numkeys_zero
      assert_equal ["a1"], r.eval("return {ARGV[1]}", 0, "a1")
    end

    # Both keys must live in one slot: in cluster mode EVAL routes by its keys
    # and a multi-key script spanning slots is rejected with CROSSSLOT.
    def test_eval_with_integer_numkeys_multiple_keys_and_args
      assert_equal %w[{1}k1 {1}k2 a1],
                   r.eval("return {KEYS[1], KEYS[2], ARGV[1]}", 2, "{1}k1", "{1}k2", "a1")
    end

    def test_eval_with_numkeys_exceeding_args_raises
      assert_raises(ArgumentError) { r.eval("return 1", 5, "only-one") }
    end

    def test_eval_with_negative_numkeys_raises
      assert_raises(ArgumentError) { r.eval("return 1", -1) }
    end

    # A numeric-but-not-Integer key count used to fall through to the
    # two-array branch, where the count itself became KEYS[1] and every
    # remaining argument was silently dropped - the same silent misassignment
    # the Integer form was fixed for. It must fail loudly instead.
    def test_eval_with_non_integer_numeric_numkeys_raises
      assert_raises(ArgumentError) { r.eval("return 1", 2.0, "k1", "k2") }
      assert_raises(ArgumentError) { r.eval("return 1", Rational(2, 1), "k1", "k2") }
    end

    # More than (keys, argv) positionally is not a supported form; the extras
    # used to be dropped without a word.
    def test_eval_with_too_many_positional_arrays_raises
      assert_raises(ArgumentError) do
        r.eval("return 1", ["k1"], ["a1"], ["extra"])
      end
    end

    def test_eval_integer_numkeys_mixed_with_keywords_raises
      assert_raises(ArgumentError) do
        r.eval("return 1", 1, "mykey", keys: ["other"])
      end
    end

    def test_eval_integer_numkeys_writes_to_the_named_key
      r.eval("redis.call('SET', KEYS[1], ARGV[1])", 1, "realkey", "realval")

      assert_equal "realval", r.get("realkey")
      assert_nil r.get("1")
    end

    def test_eval_integer_numkeys_releases_a_redlock_style_lock
      r.set("lock:job", "token-abc")
      unlock = "if redis.call('GET', KEYS[1]) == ARGV[1] then " \
               "return redis.call('DEL', KEYS[1]) else return 0 end"

      assert_equal 1, r.eval(unlock, 1, "lock:job", "token-abc")
      assert_nil r.get("lock:job")
    end

    def test_evalsha_with_integer_numkeys
      sha = r.script_load("return {KEYS[1], ARGV[1]}")

      assert_equal %w[mykey myarg], r.evalsha(sha, 1, "mykey", "myarg")
    end

    def test_evalsha_with_integer_numkeys_zero
      sha = r.script_load("return {ARGV[1]}")

      assert_equal ["a1"], r.evalsha(sha, 0, "a1")
    end

    def test_evalsha_with_numkeys_exceeding_args_raises
      sha = r.script_load("return 1")

      assert_raises(ArgumentError) { r.evalsha(sha, 5, "only-one") }
    end

    def test_eval_ro_with_integer_numkeys
      target_version "7.0" do
        assert_equal %w[mykey myarg],
                     r.eval_ro("return {KEYS[1], ARGV[1]}", 1, "mykey", "myarg")
      end
    end

    def test_evalsha_ro_with_integer_numkeys
      target_version "7.0" do
        sha = r.script_load("return {KEYS[1], ARGV[1]}")

        assert_equal %w[mykey myarg], r.evalsha_ro(sha, 1, "mykey", "myarg")
      end
    end

    # the previously-supported forms must keep working unchanged

    def test_eval_two_array_positional_form_still_works
      assert_equal %w[mykey myarg],
                   r.eval("return {KEYS[1], ARGV[1]}", ["mykey"], ["myarg"])
    end

    def test_eval_keyword_form_still_works
      assert_equal %w[mykey myarg],
                   r.eval("return {KEYS[1], ARGV[1]}", keys: ["mykey"], args: ["myarg"])
    end

    def test_evalsha_two_array_positional_form_still_works
      sha = r.script_load("return {KEYS[1], ARGV[1]}")

      assert_equal %w[mykey myarg], r.evalsha(sha, ["mykey"], ["myarg"])
    end

    # script cache lifecycle - script_load must reach the server

    def test_script_load_makes_the_script_available_on_the_server
      sha = r.script_load("return 'loaded-on-server'")

      assert_equal true, r.script_exists(sha)
      # no prior eval of this script - it is only usable if SCRIPT LOAD really
      # reached the server
      assert_equal "loaded-on-server", r.evalsha(sha)
    end

    def test_script_load_returns_the_server_computed_sha
      script = "return 'sha-check'"
      sha = r.script_load(script)

      assert_equal 40, sha.length
      assert_equal sha, r.script_load(script)
    end

    # script_load reaches the wire now, so a non-String would otherwise flatten
    # into extra SCRIPT LOAD arguments and fail as a server arity error.
    def test_script_load_rejects_a_non_string_script
      assert_raises(ArgumentError) { r.script_load(42) }
      assert_raises(ArgumentError) { r.script_load(nil) }
      assert_raises(ArgumentError) { r.script_load("") }
      assert_raises(ArgumentError) { r.script_load([]) }
    end

    # Every scripting command routes through #call, which forwards a `route:`
    # keyword that Pipeline#send_command did not accept - queuing any of them
    # raised ArgumentError instead of batching.
    def test_scripting_commands_work_inside_a_pipeline
      results = r.pipelined do |pipeline|
        pipeline.script_load("return 'from-pipeline'")
        pipeline.eval("return {KEYS[1], ARGV[1]}", 1, "pk", "pa")
      end

      assert_equal 40, results[0].length
      assert_equal %w[pk pa], results[1]
    end

    # split from the test above so the `route:` regression stays covered on
    # servers predating EVAL_RO (added in 7.0)
    def test_read_only_scripting_commands_work_inside_a_pipeline
      target_version "7.0" do
        results = r.pipelined do |pipeline|
          pipeline.eval_ro("return 'ro'", 0)
        end

        assert_equal ["ro"], results
      end
    end

    def test_eval_works_inside_a_transaction
      results = r.multi do |tx|
        tx.eval("return {KEYS[1], ARGV[1]}", 1, "tk", "ta")
      end

      assert_equal [%w[tk ta]], results
    end

    def test_script_flush_really_invalidates_the_script
      sha = r.script_load("return 'flushme'")
      assert_equal "flushme", r.evalsha(sha)

      assert_equal "OK", r.script_flush

      assert_equal false, r.script_exists(sha)
      # must not silently re-upload from a stale client-side container
      assert_raises(Valkey::CommandError) { r.evalsha(sha) }
      assert_equal false, r.script_exists(sha)
    end

    def test_evalsha_raises_for_a_never_loaded_sha
      r.script_flush
      never_loaded = "a" * 40

      assert_raises(Valkey::CommandError) { r.evalsha(never_loaded) }
    end

    def test_script_loaded_by_one_client_is_usable_by_another
      sha = r.script_load("return 'cross-client'")

      # Deliberately NOT init()'d - init flushes the shared test database and
      # would destroy the surrounding tests' keyspace. The script cache is
      # server-wide, so a bare connection is all this needs.
      other = _new_client
      begin
        assert_equal "cross-client", other.evalsha(sha)
      ensure
        other.close
      end
    end
  end
end
