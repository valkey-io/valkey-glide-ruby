# frozen_string_literal: true

module Lint
  module SortedSetCommands
    def test_zadd
      assert_equal 0, r.zcard("foo")
      assert_equal true, r.zadd("foo", 1, "s1")
      assert_equal false, r.zadd("foo", 1, "s1")
      assert_equal 1, r.zcard("foo")
      r.del "foo"

      # XX option
      assert_equal 0, r.zcard("foo")
      assert_equal false, r.zadd("foo", 1, "s1", xx: true)
      r.zadd("foo", 1, "s1")
      assert_equal false, r.zadd("foo", 2, "s1", xx: true)
      assert_equal 2, r.zscore("foo", "s1")
      r.del "foo"

      # NX option
      assert_equal 0, r.zcard("foo")
      assert_equal true, r.zadd("foo", 1, "s1", nx: true)
      assert_equal false, r.zadd("foo", 2, "s1", nx: true)
      assert_equal 1, r.zscore("foo", "s1")
      assert_equal 1, r.zcard("foo")
      r.del "foo"

      # CH option
      assert_equal 0, r.zcard("foo")
      assert_equal true, r.zadd("foo", 1, "s1", ch: true)
      assert_equal false, r.zadd("foo", 1, "s1", ch: true)
      assert_equal true, r.zadd("foo", 2, "s1", ch: true)
      assert_equal 1, r.zcard("foo")
      r.del "foo"

      # INCR option
      assert_equal 1.0, r.zadd("foo", 1, "s1", incr: true)
      assert_equal 11.0, r.zadd("foo", 10, "s1", incr: true)
      assert_equal(-Float::INFINITY, r.zadd("bar", "-inf", "s1", incr: true))
      assert_equal(+Float::INFINITY, r.zadd("bar", "+inf", "s2", incr: true))
      r.del 'foo'
      r.del 'bar'

      # Incompatible options combination
      assert_raises(Valkey::CommandError) { r.zadd("foo", 1, "s1", xx: true, nx: true) }
    end

    def test_zadd_keywords
      target_version "6.2" do
        # LT option
        r.zadd("foo", 2, "s1")

        r.zadd("foo", 3, "s1", lt: true)
        assert_equal 2.0, r.zscore("foo", "s1")

        r.zadd("foo", 1, "s1", lt: true)
        assert_equal 1.0, r.zscore("foo", "s1")

        assert_equal true, r.zadd("foo", 3, "s2", lt: true) # adds new member
        r.del "foo"

        # GT option
        r.zadd("foo", 2, "s1")

        r.zadd("foo", 1, "s1", gt: true)
        assert_equal 2.0, r.zscore("foo", "s1")

        r.zadd("foo", 3, "s1", gt: true)
        assert_equal 3.0, r.zscore("foo", "s1")

        assert_equal true, r.zadd("foo", 1, "s2", gt: true) # adds new member
        r.del "foo"

        # Incompatible options combination
        assert_raises(Valkey::CommandError) { r.zadd("foo", 1, "s1", nx: true, gt: true) }
      end
    end

    def test_variadic_zadd
      # Non-nested array with pairs
      assert_equal 0, r.zcard("foo")

      assert_equal 2, r.zadd("foo", [1, "s1", 2, "s2"])
      assert_equal 2, r.zcard("foo")

      assert_equal 1, r.zadd("foo", [4, "s1", 5, "s2", 6, "s3"])
      assert_equal 3, r.zcard("foo")

      r.del "foo"

      # Nested array with pairs
      assert_equal 0, r.zcard("foo")

      assert_equal 2, r.zadd("foo", [[1, "s1"], [2, "s2"]])
      assert_equal 2, r.zcard("foo")

      assert_equal 1, r.zadd("foo", [[4, "s1"], [5, "s2"], [6, "s3"]])
      assert_equal 3, r.zcard("foo")

      r.del "foo"

      # Empty array
      assert_equal 0, r.zcard("foo")

      assert_equal 0, r.zadd("foo", [])
      assert_equal 0, r.zcard("foo")

      r.del "foo"

      # Wrong number of arguments
      assert_raises(Valkey::CommandError) { r.zadd("foo", ["bar"]) }
      assert_raises(Valkey::CommandError) { r.zadd("foo", %w[bar qux zap]) }

      # XX option
      assert_equal 0, r.zcard("foo")
      assert_equal 0, r.zadd("foo", [1, "s1", 2, "s2"], xx: true)
      r.zadd("foo", [1, "s1", 2, "s2"])
      assert_equal 0, r.zadd("foo", [2, "s1", 3, "s2", 4, "s3"], xx: true)
      assert_equal 2, r.zscore("foo", "s1")
      assert_equal 3, r.zscore("foo", "s2")
      assert_nil r.zscore("foo", "s3")
      assert_equal 2, r.zcard("foo")
      r.del "foo"

      # NX option
      assert_equal 0, r.zcard("foo")
      assert_equal 2, r.zadd("foo", [1, "s1", 2, "s2"], nx: true)
      assert_equal 1, r.zadd("foo", [2, "s1", 3, "s2", 4, "s3"], nx: true)
      assert_equal 1, r.zscore("foo", "s1")
      assert_equal 2, r.zscore("foo", "s2")
      assert_equal 4, r.zscore("foo", "s3")
      assert_equal 3, r.zcard("foo")
      r.del "foo"

      # CH option
      assert_equal 0, r.zcard("foo")
      assert_equal 2, r.zadd("foo", [1, "s1", 2, "s2"], ch: true)
      assert_equal 2, r.zadd("foo", [1, "s1", 3, "s2", 4, "s3"], ch: true)
      assert_equal 3, r.zcard("foo")
      r.del "foo"

      # INCR option
      assert_equal 1.0, r.zadd("foo", [1, "s1"], incr: true)
      assert_equal 11.0, r.zadd("foo", [10, "s1"], incr: true)
      assert_equal(-Float::INFINITY, r.zadd("bar", ["-inf", "s1"], incr: true))
      assert_equal(+Float::INFINITY, r.zadd("bar", ["+inf", "s2"], incr: true))
      assert_raises(Valkey::CommandError) { r.zadd("foo", [1, "s1", 2, "s2"], incr: true) }
      r.del 'foo'
      r.del 'bar'

      # Incompatible options combination
      assert_raises(Valkey::CommandError) { r.zadd("foo", [1, "s1"], xx: true, nx: true) }
    end

    def test_variadic_zadd_keywords
      target_version "6.2" do
        # LT option
        r.zadd("foo", 2, "s1")

        assert_equal 1, r.zadd("foo", [3, "s1", 2, "s2"], lt: true, ch: true)
        assert_equal 2.0, r.zscore("foo", "s1")

        assert_equal 1, r.zadd("foo", [1, "s1"], lt: true, ch: true)

        r.del "foo"

        # GT option
        r.zadd("foo", 2, "s1")

        assert_equal 1, r.zadd("foo", [1, "s1", 2, "s2"], gt: true, ch: true)
        assert_equal 2.0, r.zscore("foo", "s1")

        assert_equal 1, r.zadd("foo", [3, "s1"], gt: true, ch: true)

        r.del "foo"
      end
    end

    def test_zrem
      r.zadd("foo", 1, "s1")
      r.zadd("foo", 2, "s2")

      assert_equal 2, r.zcard("foo")
      assert_equal true, r.zrem("foo", "s1")
      assert_equal false, r.zrem("foo", "s1")
      assert_equal 1, r.zcard("foo")
    end

    def test_variadic_zrem
      r.zadd("foo", 1, "s1")
      r.zadd("foo", 2, "s2")
      r.zadd("foo", 3, "s3")

      assert_equal 3, r.zcard("foo")

      assert_equal 0, r.zrem("foo", [])
      assert_equal 3, r.zcard("foo")

      assert_equal 1, r.zrem("foo", %w[s1 aaa])
      assert_equal 2, r.zcard("foo")

      assert_equal 0, r.zrem("foo", %w[bbb ccc ddd])
      assert_equal 2, r.zcard("foo")

      assert_equal 1, r.zrem("foo", %w[eee s3])
      assert_equal 1, r.zcard("foo")
    end

    def test_zincrby
      rv = r.zincrby "foo", 1, "s1"
      assert_equal 1.0, rv

      rv = r.zincrby "foo", 10, "s1"
      assert_equal 11.0, rv

      rv = r.zincrby "bar", "-inf", "s1"
      assert_equal(-Float::INFINITY, rv)

      rv = r.zincrby "bar", "+inf", "s2"
      assert_equal(+Float::INFINITY, rv)
    end

    def test_zrank
      r.zadd "foo", 1, "s1"
      r.zadd "foo", 2, "s2"
      r.zadd "foo", 3, "s3"

      assert_equal 2, r.zrank("foo", "s3")
      target_version "7.2" do
        assert_equal [2, 3], r.zrank("foo", "s3", with_score: true)
        assert_equal [2, 3], r.zrank("foo", "s3", withscore: true)
      end
    end

    def test_zrevrank
      r.zadd "foo", 1, "s1"
      r.zadd "foo", 2, "s2"
      r.zadd "foo", 3, "s3"

      assert_equal 0, r.zrevrank("foo", "s3")
      target_version "7.2" do
        assert_equal [0, 3], r.zrevrank("foo", "s3", with_score: true)
        assert_equal [0, 3], r.zrevrank("foo", "s3", withscore: true)
      end
    end
  end
end
