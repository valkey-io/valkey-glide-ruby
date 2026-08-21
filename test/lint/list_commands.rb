# frozen_string_literal: true

module Lint
  module Lists
    def test_lmove
      # Uses foo/bar keys across different hash slots
      skip("Cross-slot operation not supported in cluster mode") if cluster_mode?

      target_version "6.2" do
        r.lpush("foo", "s1")
        r.lpush("foo", "s2") # foo = [s2, s1]
        r.lpush("bar", "s3")
        r.lpush("bar", "s4") # bar = [s4, s3]

        assert_nil r.lmove("nonexistent", "foo", "LEFT", "LEFT")

        assert_equal "s2", r.lmove("foo", "foo", "LEFT", "RIGHT") # foo = [s1, s2]
        assert_equal "s1", r.lmove("foo", "foo", "LEFT", "LEFT") # foo = [s1, s2]

        assert_equal "s1", r.lmove("foo", "bar", "LEFT", "RIGHT") # foo = [s2], bar = [s4, s3, s1]
        assert_equal ["s2"], r.lrange("foo", 0, -1)
        assert_equal %w[s4 s3 s1], r.lrange("bar", 0, -1)

        assert_equal "s2", r.lmove("foo", "bar", "LEFT", "LEFT") # foo = [], bar = [s2, s4, s3, s1]
        assert_nil r.lmove("foo", "bar", "LEFT", "LEFT") # foo = [], bar = [s2, s4, s3, s1]
        assert_equal %w[s2 s4 s3 s1], r.lrange("bar", 0, -1)

        error = assert_raises(ArgumentError) do
          r.lmove("foo", "bar", "LEFT", "MIDDLE")
        end
        assert_equal "where_destination must be 'LEFT' or 'RIGHT'", error.message
      end
    end

    def test_lpush
      r.lpush "foo", "s1"
      r.lpush "foo", "s2"

      assert_equal 2, r.llen("foo")
      assert_equal "s2", r.lpop("foo")
    end

    def test_array_lpush
      assert_equal 3, r.lpush("foo", %w[s1 s2 s3])
      assert_equal 3, r.llen("foo")
      assert_equal "s3", r.lpop("foo")
    end

    def test_splat_lpush
      assert_equal 3, r.lpush("foo", "s1", "s2", "s3")
      assert_equal 3, r.llen("foo")
      assert_equal "s3", r.lpop("foo")
    end

    def test_lpushx
      r.lpushx "foo", "s1"
      r.lpush "foo", "s2"
      r.lpushx "foo", "s3"

      assert_equal 2, r.llen("foo")
      assert_equal %w[s3 s2], r.lrange("foo", 0, -1)
    end

    def test_array_lpushx
      r.lpush "foo", "s1"
      r.lpushx "foo", %w[s2 s3]

      assert_equal 3, r.llen("foo")
      assert_equal %w[s3 s2 s1], r.lrange("foo", 0, -1)
    end

    def test_splat_lpushx
      r.lpush "foo", "s1"
      r.lpushx "foo", "s2", "s3"

      assert_equal 3, r.llen("foo")
      assert_equal %w[s3 s2 s1], r.lrange("foo", 0, -1)
    end

    def test_rpush
      r.rpush "foo", "s1"
      r.rpush "foo", "s2"

      assert_equal 2, r.llen("foo")
      assert_equal "s2", r.rpop("foo")
    end

    def test_array_rpush
      assert_equal 3, r.rpush("foo", %w[s1 s2 s3])
      assert_equal 3, r.llen("foo")
      assert_equal "s3", r.rpop("foo")
    end

    def test_splat_rpush
      assert_equal 3, r.rpush("foo", "s1", "s2", "s3")
      assert_equal 3, r.llen("foo")
      assert_equal "s3", r.rpop("foo")
    end

    def test_rpushx
      r.rpushx "foo", "s1"
      r.rpush "foo", "s2"
      r.rpushx "foo", "s3"

      assert_equal 2, r.llen("foo")
      assert_equal %w[s2 s3], r.lrange("foo", 0, -1)
    end

    def test_array_rpushx
      r.rpush "foo", "s1"
      r.rpushx "foo", %w[s2 s3]

      assert_equal 3, r.llen("foo")
      assert_equal %w[s1 s2 s3], r.lrange("foo", 0, -1)
    end

    def test_splat_rpushx
      r.rpush "foo", "s1"
      r.rpushx "foo", "s2", "s3"

      assert_equal 3, r.llen("foo")
      assert_equal %w[s1 s2 s3], r.lrange("foo", 0, -1)
    end

    def test_llen
      r.rpush "foo", "s1"
      r.rpush "foo", "s2"

      assert_equal 2, r.llen("foo")
    end

    def test_lrange
      r.rpush "foo", "s1"
      r.rpush "foo", "s2"
      r.rpush "foo", "s3"

      assert_equal %w[s2 s3], r.lrange("foo", 1, -1)
      assert_equal %w[s1 s2], r.lrange("foo", 0, 1)

      assert_equal [], r.lrange("bar", 0, -1)
    end

    def test_ltrim
      r.rpush "foo", "s1"
      r.rpush "foo", "s2"
      r.rpush "foo", "s3"

      r.ltrim "foo", 0, 1

      assert_equal 2, r.llen("foo")
      assert_equal %w[s1 s2], r.lrange("foo", 0, -1)
    end

    def test_lindex
      r.rpush "foo", "s1"
      r.rpush "foo", "s2"

      assert_equal "s1", r.lindex("foo", 0)
      assert_equal "s2", r.lindex("foo", 1)
    end

    def test_lset
      r.rpush "foo", "s1"
      r.rpush "foo", "s2"

      assert_equal "s2", r.lindex("foo", 1)
      assert r.lset("foo", 1, "s3")
      assert_equal "s3", r.lindex("foo", 1)

      assert_raises Valkey::CommandError do
        r.lset("foo", 4, "s3")
      end
    end

    def test_lrem
      r.rpush "foo", "s1"
      r.rpush "foo", "s2"

      assert_equal 1, r.lrem("foo", 1, "s1")
      assert_equal ["s2"], r.lrange("foo", 0, -1)
    end

    def test_lpop
      r.rpush "foo", "s1"
      r.rpush "foo", "s2"

      assert_equal 2, r.llen("foo")
      assert_equal "s1", r.lpop("foo")
      assert_equal 1, r.llen("foo")
      assert_nil r.lpop("nonexistent")
    end

    def test_lpop_count
      target_version("6.2") do
        r.rpush "foo", "s1"
        r.rpush "foo", "s2"

        assert_equal 2, r.llen("foo")
        assert_equal %w[s1 s2], r.lpop("foo", 2)
        assert_equal 0, r.llen("foo")
      end
    end

    def test_rpop
      r.rpush "foo", "s1"
      r.rpush "foo", "s2"

      assert_equal 2, r.llen("foo")
      assert_equal "s2", r.rpop("foo")
      assert_equal 1, r.llen("foo")
      assert_nil r.rpop("nonexistent")
    end

    def test_rpop_count
      target_version("6.2") do
        r.rpush "foo", "s1"
        r.rpush "foo", "s2"

        assert_equal 2, r.llen("foo")
        assert_equal %w[s2 s1], r.rpop("foo", 2)
        assert_equal 0, r.llen("foo")
      end
    end

    def test_linsert
      r.rpush "foo", "s1"
      r.rpush "foo", "s3"
      r.linsert "foo", :before, "s3", "s2"

      assert_equal %w[s1 s2 s3], r.lrange("foo", 0, -1)

      assert_raises(Valkey::CommandError) do
        r.linsert "foo", :anywhere, "s3", "s2"
      end
    end

    def test_blmpop
      target_version('7.0') do
        assert_nil r.blmpop(0.1, '{1}foo')

        r.lpush('{1}foo', %w[a b c d e f g])
        assert_equal({ '{1}foo' => ['g'] }, r.blmpop(0.1, '{1}foo'))
        assert_equal({ '{1}foo' => %w[f e] }, r.blmpop(0.1, '{1}foo', count: 2))

        r.lpush('{1}foo2', %w[a b])
        assert_equal({ '{1}foo' => ['a'] }, r.blmpop(0.1, '{1}foo', '{1}foo2', modifier: "RIGHT"))
      end
    end

    def test_lmpop
      target_version('7.0') do
        assert_nil r.lmpop('{1}foo')

        r.lpush('{1}foo', %w[a b c d e f g])

        assert_equal({ '{1}foo' => ['g'] }, r.lmpop('{1}foo'))
        assert_equal({ '{1}foo' => %w[f e] }, r.lmpop('{1}foo', count: 2))

        r.lpush('{1}foo2', %w[a b])
        assert_equal({ '{1}foo' => ['a'] }, r.lmpop('{1}foo', '{1}foo2', modifier: "RIGHT"))
      end
    end

    # --- Blocking list commands -------------------------------------------
    #
    # Every test below pushes a value first so the command returns immediately
    # instead of actually blocking, except where the timeout path is the point.
    # Timeouts are kept at 1s so the suite stays fast.

    def test_blpop
      r.rpush("{1}foo", "s1")

      # Single key, no explicit timeout.
      assert_equal ["{1}foo", "s1"], r.blpop("{1}foo")

      # Single key with an explicit timeout.
      r.rpush("{1}foo", "s2")
      assert_equal ["{1}foo", "s2"], r.blpop("{1}foo", timeout: 1)

      # BLPOP pops from the head.
      r.rpush("{1}foo", "head", "tail")
      assert_equal ["{1}foo", "head"], r.blpop("{1}foo", timeout: 1)
      assert_equal ["tail"], r.lrange("{1}foo", 0, -1)
    end

    def test_blpop_multiple_keys
      r.rpush("{1}foo2", "s2")

      # Array form: keys are checked in the order given, so the first
      # non-empty one wins even though it is not first in the list.
      assert_equal ["{1}foo2", "s2"], r.blpop(["{1}foo", "{1}foo2"], timeout: 1)

      # Splat form should behave identically to the array form.
      r.rpush("{1}foo", "s1")
      assert_equal ["{1}foo", "s1"], r.blpop("{1}foo", "{1}foo2", timeout: 1)
    end

    # Splat and Array forms may be mixed; `keys` is flattened one level. This
    # covers the mixed shape end-to-end, but note it does not isolate _bpop's
    # flatten: build_command_args in lib/valkey.rb flattens nested Arrays too,
    # so the call still succeeds without it. The argv guards below are what
    # observe _bpop's own output.
    def test_blpop_mixed_key_forms
      r.rpush("{1}foo3", "s3")

      assert_equal ["{1}foo3", "s3"], r.blpop("{1}foo", ["{1}foo2", "{1}foo3"], timeout: 1)
    end

    # Float timeouts must survive to a live server, not just into argv.
    def test_blpop_accepts_float_timeout
      r.rpush("{1}foo", "s1")

      assert_equal ["{1}foo", "s1"], r.blpop("{1}foo", timeout: 1.5)
    end

    def test_blpop_timeout_returns_nil
      assert_nil r.blpop("{1}missing", timeout: 1)
    end

    def test_blpop_validates_timeout
      error = assert_raises(ArgumentError) do
        r.blpop("{1}foo", timeout: "1")
      end
      assert_equal "timeout must be an Integer or Float, got: String", error.message
    end

    def test_brpop
      r.rpush("{1}foo", "s1")

      # Single key, no explicit timeout.
      assert_equal ["{1}foo", "s1"], r.brpop("{1}foo")

      # Single key with an explicit timeout.
      r.rpush("{1}foo", "s2")
      assert_equal ["{1}foo", "s2"], r.brpop("{1}foo", timeout: 1)

      # BRPOP pops from the tail.
      r.rpush("{1}foo", "head", "tail")
      assert_equal ["{1}foo", "tail"], r.brpop("{1}foo", timeout: 1)
      assert_equal ["head"], r.lrange("{1}foo", 0, -1)
    end

    def test_brpop_multiple_keys
      r.rpush("{1}foo2", "s2")

      assert_equal ["{1}foo2", "s2"], r.brpop(["{1}foo", "{1}foo2"], timeout: 1)

      r.rpush("{1}foo", "s1")
      assert_equal ["{1}foo", "s1"], r.brpop("{1}foo", "{1}foo2", timeout: 1)
    end

    # @see #test_blpop_mixed_key_forms
    def test_brpop_mixed_key_forms
      r.rpush("{1}foo3", "s3")

      assert_equal ["{1}foo3", "s3"], r.brpop("{1}foo", ["{1}foo2", "{1}foo3"], timeout: 1)
    end

    def test_brpop_accepts_float_timeout
      r.rpush("{1}foo", "s1")

      assert_equal ["{1}foo", "s1"], r.brpop("{1}foo", timeout: 1.5)
    end

    def test_brpop_timeout_returns_nil
      assert_nil r.brpop("{1}missing", timeout: 1)
    end

    def test_brpop_builds_argv_with_timeout_as_last_token
      with_timeout = capture_blocking_argv { r.brpop("{1}missing", timeout: 1) }
      assert_equal ["{1}missing", 1], with_timeout

      # No explicit timeout still appends the 0 sentinel.
      without_timeout = capture_blocking_argv { r.brpop("{1}missing") }
      assert_equal ["{1}missing", 0], without_timeout

      # Floats survive as-is.
      float_timeout = capture_blocking_argv { r.brpop("{1}missing", timeout: 1.5) }
      assert_equal ["{1}missing", 1.5], float_timeout
    end

    # Same guard for blpop, including the array key form where the options Hash
    # sits behind an Array argument, and the splat form.
    def test_blpop_builds_argv_with_timeout_as_last_token
      single_key = capture_blocking_argv { r.blpop("{1}missing", timeout: 1) }
      assert_equal ["{1}missing", 1], single_key

      array_form = capture_blocking_argv { r.blpop(["{1}missing", "{1}missing2"], timeout: 1) }
      assert_equal ["{1}missing", "{1}missing2", 1], array_form

      splat_form = capture_blocking_argv { r.blpop("{1}missing", "{1}missing2", timeout: 1) }
      assert_equal ["{1}missing", "{1}missing2", 1], splat_form
    end

    # blmove's timeout must likewise land as the final argv token.
    def test_blmove_builds_argv_with_timeout_as_last_token
      with_timeout = capture_blocking_argv { r.blmove("{1}src", "{1}dst", "LEFT", "RIGHT", timeout: 1) }
      assert_equal ["{1}src", "{1}dst", "LEFT", "RIGHT", 1], with_timeout

      without_timeout = capture_blocking_argv { r.blmove("{1}src", "{1}dst", "RIGHT", "LEFT") }
      assert_equal ["{1}src", "{1}dst", "RIGHT", "LEFT", 0], without_timeout
    end

    def test_brpop_honours_timeout_against_server
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_nil r.brpop("{1}missing", timeout: 1)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert_operator elapsed, :>=, 0.5, "brpop returned too early to have waited for the timeout"
    end

    def test_blmove
      # Uses foo/bar keys across different hash slots
      skip("Cross-slot operation not supported in cluster mode") if cluster_mode?

      r.rpush("foo", "a", "b") # foo = [a, b]

      # LEFT -> RIGHT: pop the head of source, append to destination.
      assert_equal "a", r.blmove("foo", "bar", "LEFT", "RIGHT", timeout: 1)
      assert_equal ["b"], r.lrange("foo", 0, -1)
      assert_equal ["a"], r.lrange("bar", 0, -1)

      # RIGHT -> LEFT: pop the tail of source, prepend to destination.
      assert_equal "b", r.blmove("foo", "bar", "RIGHT", "LEFT", timeout: 1)
      assert_equal [], r.lrange("foo", 0, -1)
      assert_equal %w[b a], r.lrange("bar", 0, -1)

      # Source is now empty, so the call times out and returns nil.
      assert_nil r.blmove("foo", "bar", "RIGHT", "LEFT", timeout: 1)
    end

    def test_blmove_without_explicit_timeout_returns_immediately_when_data_present
      skip("Cross-slot operation not supported in cluster mode") if cluster_mode?

      r.rpush("foo", "only")

      assert_equal "only", r.blmove("foo", "bar", "LEFT", "LEFT")
      assert_equal ["only"], r.lrange("bar", 0, -1)
    end

    def test_blmove_validates_wheres
      error = assert_raises(ArgumentError) do
        r.blmove("{1}foo", "{1}bar", "LEFT", "MIDDLE", timeout: 1)
      end
      assert_equal "where_destination must be 'LEFT' or 'RIGHT'", error.message
    end

    def test_blmove_validates_timeout
      error = assert_raises(ArgumentError) do
        r.blmove("{1}foo", "{1}bar", "LEFT", "RIGHT", timeout: "1")
      end
      assert_equal "timeout must be an Integer or Float, got: String", error.message
    end

    def test_rpoplpush
      # Uses foo/bar keys across different hash slots
      skip("Cross-slot operation not supported in cluster mode") if cluster_mode?

      r.rpush("foo", "a", "b") # foo = [a, b]

      # The tail of foo becomes the head of bar.
      assert_equal "b", r.rpoplpush("foo", "bar") # foo = [a], bar = [b]
      assert_equal ["a"], r.lrange("foo", 0, -1)
      assert_equal ["b"], r.lrange("bar", 0, -1)

      assert_equal "a", r.rpoplpush("foo", "bar") # foo = [], bar = [a, b]
      assert_equal [], r.lrange("foo", 0, -1)
      assert_equal %w[a b], r.lrange("bar", 0, -1)

      # An empty list is deleted, so source no longer exists.
      assert_nil r.rpoplpush("foo", "bar")
      assert_nil r.rpoplpush("nonexistent", "bar")
      assert_equal %w[a b], r.lrange("bar", 0, -1)
    end

    # Currying guard: rpoplpush must dispatch LMOVE with the exact argv the
    # documented replacement builds -- nothing added, reordered or translated.
    def test_rpoplpush_is_equivalent_to_lmove_right_left
      facade_type, facade_argv = capture_blocking_call { r.rpoplpush("{1}src", "{1}dst") }
      lmove_type, lmove_argv = capture_blocking_call { r.lmove("{1}src", "{1}dst", "RIGHT", "LEFT") }

      assert_equal Valkey::RequestType::LMOVE, facade_type
      assert_equal ["{1}src", "{1}dst", "RIGHT", "LEFT"], facade_argv

      assert_equal lmove_type, facade_type
      assert_equal lmove_argv, facade_argv
    end

    def test_brpoplpush
      # Uses foo/bar keys across different hash slots
      skip("Cross-slot operation not supported in cluster mode") if cluster_mode?

      r.rpush("foo", "a", "b") # foo = [a, b]

      assert_equal "b", r.brpoplpush("foo", "bar", timeout: 1) # foo = [a], bar = [b]
      assert_equal ["a"], r.lrange("foo", 0, -1)
      assert_equal ["b"], r.lrange("bar", 0, -1)

      assert_equal "a", r.brpoplpush("foo", "bar", timeout: 1) # foo = [], bar = [a, b]
      assert_equal [], r.lrange("foo", 0, -1)
      assert_equal %w[a b], r.lrange("bar", 0, -1)

      # Source is now empty, so the call times out and returns nil.
      assert_nil r.brpoplpush("foo", "bar", timeout: 1)
    end

    def test_brpoplpush_without_explicit_timeout_returns_immediately_when_data_present
      skip("Cross-slot operation not supported in cluster mode") if cluster_mode?

      r.rpush("foo", "only")

      assert_equal "only", r.brpoplpush("foo", "bar")
      assert_equal ["only"], r.lrange("bar", 0, -1)
    end

    # Same guard as test_blmove_builds_argv_with_timeout_as_last_token, applied to
    # the facade: the timeout must survive the extra hop and still land as the
    # final argv token rather than being dropped (== block forever).
    def test_brpoplpush_builds_argv_with_timeout_as_last_token
      with_timeout = capture_blocking_argv { r.brpoplpush("{1}src", "{1}dst", timeout: 1) }
      assert_equal ["{1}src", "{1}dst", "RIGHT", "LEFT", 1], with_timeout

      # No explicit timeout still appends the 0 sentinel.
      without_timeout = capture_blocking_argv { r.brpoplpush("{1}src", "{1}dst") }
      assert_equal ["{1}src", "{1}dst", "RIGHT", "LEFT", 0], without_timeout

      # Floats survive as-is.
      float_timeout = capture_blocking_argv { r.brpoplpush("{1}src", "{1}dst", timeout: 1.5) }
      assert_equal ["{1}src", "{1}dst", "RIGHT", "LEFT", 1.5], float_timeout
    end

    # Currying guard for the blocking facade, timeout included.
    def test_brpoplpush_is_equivalent_to_blmove_right_left
      facade_type, facade_argv = capture_blocking_call { r.brpoplpush("{1}src", "{1}dst", timeout: 1) }
      blmove_type, blmove_argv = capture_blocking_call do
        r.blmove("{1}src", "{1}dst", "RIGHT", "LEFT", timeout: 1)
      end

      assert_equal Valkey::RequestType::BLMOVE, facade_type
      assert_equal ["{1}src", "{1}dst", "RIGHT", "LEFT", 1], facade_argv

      assert_equal blmove_type, facade_type
      assert_equal blmove_argv, facade_argv
    end

    # The facade adds no validation of its own; it inherits blmove's.
    def test_brpoplpush_validates_timeout
      error = assert_raises(ArgumentError) do
        r.brpoplpush("{1}src", "{1}dst", timeout: "1")
      end
      assert_equal "timeout must be an Integer or Float, got: String", error.message
    end

    private

    # Invokes a blocking list command while intercepting send_command, and
    # returns the argv the client built -- without issuing a real blocking call.
    # Mirrors capture_cluster_failover_args in test/lint/cluster_commands.rb and
    # capture_call_args in test/unit/commands/generic_commands_test.rb.
    def capture_blocking_argv(&invocation)
      captured = nil
      recorder = lambda do |_request_type, args = [], **_opts, &_block|
        captured = args
        nil
      end
      r.stub(:send_command, recorder, &invocation)
      captured
    end

    # Same interception as capture_blocking_argv, but also returns the
    # RequestType. Used by the rpoplpush/brpoplpush currying guards, where the
    # request type is half the claim: a facade that built the right argv under
    # the wrong request type would still be a different command.
    #
    # @return [[Integer, Array]] the request type and argv the client built
    def capture_blocking_call(&invocation)
      captured_type = nil
      captured_args = nil
      recorder = lambda do |request_type, args = [], **_opts, &_block|
        captured_type = request_type
        captured_args = args
        nil
      end
      r.stub(:send_command, recorder, &invocation)
      [captured_type, captured_args]
    end
  end
end
