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
      skip("Multi-db operations not supported in this configuration")
      target_version("6.2") do
        r.set "foo", "s1"
        r.set "bar", "s2"

        # Basic copy
        assert_equal true, r.copy("foo", "baz")
        assert_equal "s1", r.get("baz")

        # Copy to existing key without replace returns false
        assert_equal false, r.copy("foo", "bar")
        assert_equal "s2", r.get("bar")

        # Copy with replace: true overwrites destination
        assert_equal true, r.copy("foo", "bar", replace: true)
        assert_equal "s1", r.get("bar")

        # Source key is unchanged after all operations
        assert_equal "s1", r.get("foo")

        # Cross-database copy using dedicated clients per database
        db14 = _new_client(db: 14)
        db15 = _new_client(db: 15)

        db14.flushdb
        db15.flushdb

        db14.set "foo", "s1"

        # Copy from db14 to db15 — destination key doesn't exist yet
        assert_equal true, db14.copy("foo", "newkey", db: 15)
        assert_equal "s1", db14.get("foo")    # source unchanged
        assert_equal "s1", db15.get("newkey") # destination created

        # Copy to existing key in db15 without replace returns false
        assert_equal false, db14.copy("foo", "newkey", db: 15)

        # Copy to existing key in db15 with replace: true succeeds
        db14.set "foo", "s2"
        assert_equal true, db14.copy("foo", "newkey", db: 15, replace: true)
        assert_equal "s2", db15.get("newkey")
      ensure
        db14&.close
        db15&.close
      end
    end

    def test_del
      # Uses untagged keys across different hash slots
      skip("Cross-slot operation not supported in cluster mode") if cluster_mode?

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
      # Uses untagged keys across different hash slots
      skip("Cross-slot operation not supported in cluster mode") if cluster_mode?

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
      skip("Multi-db operations not supported in this configuration")
      db14 = _new_client(db: 14)
      db15 = _new_client(db: 15)

      db14.flushdb
      db15.flushdb

      # Set up: "bar" exists in db14, "foo" and "bar" exist in db15
      db14.set "bar", "s3"
      db15.set "foo", "s1"
      db15.set "bar", "s2"

      # Move "foo" from db15 to db14 — should succeed
      assert_equal true, db15.move("foo", 14)
      assert_nil db15.get("foo")
      assert_equal "s1", db14.get("foo")

      # Move "bar" from db15 to db14 — should fail because "bar" already exists in db14
      assert_equal false, db15.move("bar", 14)
      assert_equal "s2", db15.get("bar")
      assert_equal "s3", db14.get("bar")
    ensure
      db14&.close
      db15&.close
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
      # Uses foo/bar keys across different hash slots
      skip("Cross-slot operation not supported in cluster mode") if cluster_mode?

      r.set("foo", "s1")
      r.rename "foo", "bar"

      assert_equal "s1", r.get("bar")
      assert_nil r.get("foo")
    end

    def test_renamenx
      # Uses foo/bar keys across different hash slots
      skip("Cross-slot operation not supported in cluster mode") if cluster_mode?

      r.set("foo", "s1")
      r.set("bar", "s2")

      assert_equal false, r.renamenx("foo", "bar")

      assert_equal "s1", r.get("foo")
      assert_equal "s2", r.get("bar")
    end

    def test_scan
      # The set_some_keys method sets both tagged and untagged keys
      # In cluster mode, scan only sees keys on the node being scanned
      skip("SCAN with match pattern may not see all keys in cluster mode") if cluster_mode?

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

    # Keys command tests

    def test_keys
      r.set("key:1", "value1")
      r.set("key:2", "value2")
      r.set("other", "value3")

      result = r.keys("key:*")
      assert_kind_of Array, result
      assert_equal 2, result.size
      assert_includes result, "key:1"
      assert_includes result, "key:2"
    end

    def test_keys_default_pattern
      r.set("foo", "bar")

      result = r.keys
      assert_kind_of Array, result
      assert_includes result, "foo"
    end

    def test_keys_no_match
      r.set("foo", "bar")

      result = r.keys("nonexistent:*")
      assert_kind_of Array, result
      assert_equal 0, result.size
    end

    # Migrate command tests

    def test_migrate_requires_host
      assert_raises(ArgumentError) do
        r.migrate("foo", port: 6380)
      end
    end

    def test_migrate_requires_port
      assert_raises(ArgumentError) do
        r.migrate("foo", host: "127.0.0.1")
      end
    end

    def test_migrate
      skip("MIGRATE requires a second Valkey instance")

      r.set("migrate:key", "value")
      result = r.migrate("migrate:key", host: "127.0.0.1", port: 6380, db: 0, timeout: 1000)
      assert_equal "OK", result
    end

    def test_migrate_with_copy_replace
      skip("MIGRATE requires a second Valkey instance")

      r.set("migrate:key", "value")
      result = r.migrate("migrate:key", host: "127.0.0.1", port: 6380, copy: true, replace: true)
      assert_equal "OK", result
    end

    def test_migrate_multiple_keys
      skip("MIGRATE requires a second Valkey instance")

      r.set("migrate:key1", "value1")
      r.set("migrate:key2", "value2")
      result = r.migrate(%w[migrate:key1 migrate:key2], host: "127.0.0.1", port: 6380)
      assert_equal "OK", result
    end

    # WAITAOF command tests

    def test_waitaof
      result = r.waitaof(0, 0, 0)
      assert_kind_of Array, result
      assert_equal 2, result.size
      assert_kind_of Integer, result[0]
      assert_kind_of Integer, result[1]
    rescue Valkey::CommandError => e
      if e.message.include?("WAITAOF") || e.message.include?("unknown") || e.message.include?("AOF")
        skip("WAITAOF not available: #{e.message}")
      end
      raise
    end

    def test_waitaof_with_timeout
      result = r.waitaof(0, 0, 100)
      assert_kind_of Array, result
      assert_equal 2, result.size
    rescue Valkey::CommandError => e
      if e.message.include?("WAITAOF") || e.message.include?("unknown") || e.message.include?("AOF")
        skip("WAITAOF not available: #{e.message}")
      end
      raise
    end
  end
end
