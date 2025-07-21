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

    def test_zcard
      assert_equal 0, r.zcard("foo")

      r.zadd "foo", 1, "s1"

      assert_equal 1, r.zcard("foo")
    end

    def test_zscore
      r.zadd "foo", 1, "s1"

      assert_equal 1.0, r.zscore("foo", "s1")

      assert_nil r.zscore("foo", "s2")
      assert_nil r.zscore("bar", "s1")

      r.zadd "bar", "-inf", "s1"
      r.zadd "bar", "+inf", "s2"
      assert_equal(-Float::INFINITY, r.zscore("bar", "s1"))
      assert_equal(+Float::INFINITY, r.zscore("bar", "s2"))
    end

    def test_zmscore
      target_version("6.2") do
        r.zadd "foo", 1, "s1"

        assert_equal [1.0], r.zmscore("foo", "s1")
        assert_equal [nil], r.zmscore("foo", "s2")

        r.zadd "foo", "-inf", "s2"
        r.zadd "foo", "+inf", "s3"
        assert_equal [1.0, nil], r.zmscore("foo", "s1", "s4")
        assert_equal [-Float::INFINITY, +Float::INFINITY], r.zmscore("foo", "s2", "s3")
      end
    end

    def test_zlexcount
      r.zadd 'foo', 0, 'aaren'
      r.zadd 'foo', 0, 'abagael'
      r.zadd 'foo', 0, 'abby'
      r.zadd 'foo', 0, 'abbygail'

      assert_equal 4, r.zlexcount('foo', '[a', "[a\xff")
      assert_equal 4, r.zlexcount('foo', '[aa', "[ab\xff")
      assert_equal 3, r.zlexcount('foo', '(aaren', "[ab\xff")
      assert_equal 2, r.zlexcount('foo', '[aba', '(abbygail')
      assert_equal 1, r.zlexcount('foo', '(aaren', '(abby')
    end

    def test_zcount
      r.zadd 'foo', 1, 's1'
      r.zadd 'foo', 2, 's2'
      r.zadd 'foo', 3, 's3'

      assert_equal 2, r.zcount('foo', 2, 3)
    end

    def test_zunionstore_expand
      r.zadd('{1}foo', %w[0 a 1 b 2 c])
      r.zadd('{1}bar', %w[0 c 1 d 2 e])
      assert_equal 5, r.zunionstore('{1}baz', %w[{1}foo {1}bar])
    end

    def test_zinterstore_expand
      r.zadd '{1}foo', %w[0 s1 1 s2 2 s3]
      r.zadd '{1}bar', %w[0 s3 1 s4 2 s5]
      assert_equal 1, r.zinterstore('{1}baz', %w[{1}foo {1}bar], weights: [2.0, 3.0])
    end

    def test_zscan
      r.zadd('foo', %w[0 a 1 b 2 c])
      expected = ['0', [['a', 0.0], ['b', 1.0], ['c', 2.0]]]
      assert_equal expected, r.zscan('foo', 0)
    end
  end
end
