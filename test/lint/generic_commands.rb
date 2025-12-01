# frozen_string_literal: true

module Lint
  module GenericCommands
    def set_some_keys
      valkey.set('key1', 'Hello')
      valkey.set('key2', 'World')

      valkey.set('{key}1', 'Hello')
      valkey.set('{key}2', 'World')
    end

    def test_copy
      target_version("6.2") do
        with_db(14) do
          r.flushdb

          r.set "foo", "s1"
          r.set "bar", "s2"

          assert r.copy("foo", "baz")
          assert_equal "s1", r.get("baz")

          assert !r.copy("foo", "bar")

          assert r.copy("foo", "bar", replace: true)
          assert_equal "s1", r.get("bar")
        end

        with_db(15) do
          r.set "foo", "s3"
          r.set "bar", "s4"
        end

        with_db(14) do
          assert r.copy("foo", "baz", db: 15)
          assert_equal "s1", r.get("foo")

          assert !r.copy("foo", "bar", db: 15)
          assert r.copy("foo", "bar", db: 15, replace: true)
        end

        with_db(15) do
          assert_equal "s1", r.get("baz")
          assert_equal "s1", r.get("bar")
        end
      end
    end

    def test_del
      r.set "foo", "s1"
      r.set "bar", "s2"
      r.set "baz", "s3"

      assert_equal %w[bar baz foo], all_keys

      assert_equal 0, r.del("")

      assert_equal 1, r.del("foo")

      assert_equal %w[bar baz], all_keys

      assert_equal 2, r.del("bar", "baz")

      assert_equal [], all_keys
    end

    def test_del_with_array_argument
      r.set "foo", "s1"
      r.set "bar", "s2"
      r.set "baz", "s3"

      assert_equal %w[bar baz foo], all_keys

      assert_equal 0, r.del([])

      assert_equal 1, r.del(["foo"])

      assert_equal %w[bar baz], all_keys

      assert_equal 2, r.del(%w[bar baz])

      assert_equal [], all_keys
    end

    def test_dump_and_restore
      r.set("foo", "a")
      v = r.dump("foo")
      r.del("foo")

      assert r.restore("foo", 1000, v)
      assert_equal "a", r.get("foo")
      assert [0, 1].include? r.ttl("foo")

      r.rpush("bar", %w[b c d])
      w = r.dump("bar")
      r.del("bar")

      assert r.restore("bar", 1000, w)
      assert_equal %w[b c d], r.lrange("bar", 0, -1)
      assert [0, 1].include? r.ttl("bar")

      r.set("bar", "somethingelse")
      assert_raises(Valkey::CommandError) { r.restore("bar", 1000, w) } # ensure by default replace is false
      assert_raises(Valkey::CommandError) { r.restore("bar", 1000, w, replace: false) }
      assert_equal "somethingelse", r.get("bar")
      assert r.restore("bar", 1000, w, replace: true)
      assert_equal %w[b c d], r.lrange("bar", 0, -1)
      assert [0, 1].include? r.ttl("bar")
    end

    def test_exists
      assert_equal 0, r.exists("foo")

      r.set("foo", "s1")

      assert_equal 1, r.exists("foo")
      assert_equal 1, r.exists(["foo"])
    end

    def test_variadic_exists
      assert_equal 0, r.exists("{1}foo", "{1}bar")

      r.set("{1}foo", "s1")

      assert_equal 1, r.exists("{1}foo", "{1}bar")

      r.set("{1}bar", "s2")

      assert_equal 2, r.exists("{1}foo", "{1}bar")
      assert_equal 2, r.exists(["{1}foo", "{1}bar"])
    end

    def test_exists?
      assert_equal false, r.exists?("{1}foo", "{1}bar")

      r.set("{1}foo", "s1")

      assert_equal true, r.exists?("{1}foo")
      assert_equal true, r.exists?(["{1}foo"])

      r.set("{1}bar", "s1")

      assert_equal true, r.exists?("{1}foo", "{1}bar")
      assert_equal true, r.exists?(["{1}foo", "{1}bar"])
    end

    def test_expire
      r.set("foo", "s1")
      assert r.expire("foo", 2)
      assert_in_range 0..2, r.ttl("foo")

      target_version "7.0.0" do
        r.set("bar", "s2")
        refute r.expire("bar", 5, xx: true)
        assert r.expire("bar", 5, nx: true)
        refute r.expire("bar", 5, nx: true)
        assert r.expire("bar", 5, xx: true)

        r.expire("bar", 10)
        refute r.expire("bar", 15, lt: true)
        refute r.expire("bar", 5, gt: true)
        assert r.expire("bar", 15, gt: true)
        assert r.expire("bar", 5, lt: true)
      end
    end

    def test_expireat
      r.set("foo", "s1")
      assert r.expireat("foo", (Time.now + 2).to_i)
      assert_in_range 0..2, r.ttl("foo")
    end

    def test_expireat_keywords
      target_version "7.0.0" do
        r.set("bar", "s2")
        refute r.expireat("bar", (Time.now + 5).to_i, xx: true)
        assert r.expireat("bar", (Time.now + 5).to_i, nx: true)
        refute r.expireat("bar", (Time.now + 5).to_i, nx: true)
        assert r.expireat("bar", (Time.now + 5).to_i, xx: true)

        r.expireat("bar", (Time.now + 10).to_i)
        refute r.expireat("bar", (Time.now + 15).to_i, lt: true)
        refute r.expireat("bar", (Time.now + 5).to_i, gt: true)
        assert r.expireat("bar", (Time.now + 15).to_i, gt: true)
        assert r.expireat("bar", (Time.now + 5).to_i, lt: true)
      end
    end

    def test_expiretime
      target_version "7.0.0" do
        r.set("foo", "blar")
        assert_equal(-1, r.expiretime("foo"))

        exp_time = (Time.now + 2).to_i
        r.expireat("foo", exp_time)
        assert_equal exp_time, r.expiretime("foo")

        assert_equal(-2, r.expiretime("key-that-exists-not"))
      end
    end

    def test_move
      r.select 14
      r.flushdb

      r.set "bar", "s3"

      r.select 15

      r.set "foo", "s1"
      r.set "bar", "s2"

      assert r.move("foo", 14)
      assert_nil r.get("foo")

      assert !r.move("bar", 14)
      assert_equal "s2", r.get("bar")

      r.select 14

      assert_equal "s1", r.get("foo")
      assert_equal "s3", r.get("bar")
    end

    def test_object
      r.lpush "list", "value"

      assert_equal 1, r.object(:refcount, "list")
      encoding = r.object(:encoding, "list")
      assert %w[ziplist quicklist listpack].include?(encoding), "Wrong encoding for list"
      assert r.object(:idletime, "list").is_a?(Integer)
    end

    def test_persist
      r.set("foo", "s1")
      r.expire("foo", 1)
      r.persist("foo")

      assert(r.ttl("foo") == -1)
    end

    def test_pexpire
      r.set("foo", "s1")
      assert r.pexpire("foo", 2000)
      assert_in_range 0..2, r.ttl("foo")
    end

    def test_pexpire_keywords
      target_version "7.0.0" do
        r.set("bar", "s2")
        refute r.pexpire("bar", 5_000, xx: true)
        assert r.pexpire("bar", 5_000, nx: true)
        refute r.pexpire("bar", 5_000, nx: true)
        assert r.pexpire("bar", 5_000, xx: true)

        r.pexpire("bar", 10_000)
        refute r.pexpire("bar", 15_000, lt: true)
        refute r.pexpire("bar", 5_000, gt: true)
        assert r.pexpire("bar", 15_000, gt: true)
        assert r.pexpire("bar", 5_000, lt: true)
      end
    end

    def test_pexpireat
      r.set("foo", "s1")
      assert r.pexpireat("foo", (Time.now + 2).to_i * 1_000)
      assert_in_range 0..2, r.ttl("foo")
    end

    def test_pexpireat_keywords
      target_version "7.0.0" do
        r.set("bar", "s2")
        refute r.pexpireat("bar", (Time.now + 5).to_i * 1_000, xx: true)
        assert r.pexpireat("bar", (Time.now + 5).to_i * 1_000, nx: true)
        refute r.pexpireat("bar", (Time.now + 5).to_i * 1_000, nx: true)
        assert r.pexpireat("bar", (Time.now + 5).to_i * 1_000, xx: true)

        r.pexpireat("bar", (Time.now + 10).to_i * 1_000)
        refute r.pexpireat("bar", (Time.now + 15).to_i * 1_000, lt: true)
        refute r.pexpireat("bar", (Time.now + 5).to_i * 1_000, gt: true)
        assert r.pexpireat("bar", (Time.now + 15).to_i * 1_000, gt: true)
        assert r.pexpireat("bar", (Time.now + 5).to_i * 1_000, lt: true)
      end
    end

    def test_pexpiretime
      target_version "7.0.0" do
        r.set("foo", "blar")
        assert_equal(-1, r.pexpiretime("foo"))

        exp_time = (Time.now + 2).to_i * 1_000
        r.pexpireat("foo", exp_time)
        assert_equal exp_time, r.pexpiretime("foo")

        assert_equal(-2, r.pexpiretime("key-that-exists-not"))
      end
    end

    def test_pttl
      r.set("foo", "s1")
      r.expire("foo", 2)
      assert_in_range 1..2000, r.pttl("foo")
    end

    def test_rename
      r.set("foo", "s1")
      r.rename "foo", "bar"

      assert_equal "s1", r.get("bar")
      assert_nil r.get("foo")
    end

    def test_renamenx
      r.set("foo", "s1")
      r.set("bar", "s2")

      assert_equal false, r.renamenx("foo", "bar")

      assert_equal "s1", r.get("foo")
      assert_equal "s2", r.get("bar")
    end

    def test_scan
      set_some_keys

      cursor = 0
      all_keys = []
      loop do
        cursor, keys = valkey.scan(cursor, match: '{key}*')
        all_keys += keys
        break if cursor == '0'
      end

      assert_equal 2, all_keys.uniq.size
    end

    def test_type
      assert_equal "none", r.type("foo")

      r.set("foo", "s1")

      assert_equal "string", r.type("foo")
    end

    def test_ttl
      r.set("foo", "s1")
      r.expire("foo", 2)
      assert_in_range 0..2, r.ttl("foo")
    end

    def test_wait
      assert_equal r.wait(0, 0), 0
    end
  end
end
