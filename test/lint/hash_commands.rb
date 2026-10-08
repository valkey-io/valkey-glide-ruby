# frozen_string_literal: true

module Lint
  module HashCommands
    extend Helper::Parameterized

    parameterized_test(
      :test_hgetdel_single_field,
      protocol: %i[resp2 resp3]
    ) do |protocol|
      client = nil
      target_version "9.1" do
        client = _new_client(protocol: protocol)
        key = "hgetdel-single-field"
        client.hset(key, "requested", "value", "preserved", "keep")

        assert_equal ["value"], client.hgetdel(key, "requested")
        assert_nil client.hget(key, "requested")
        assert_equal "keep", client.hget(key, "preserved")
      end
    ensure
      client&.close
    end

    parameterized_test(
      :test_hgetdel_variadic_and_array_fields,
      protocol: %i[resp2 resp3]
    ) do |protocol|
      client = nil
      target_version "9.1" do
        client = _new_client(protocol: protocol)
        variadic_key = "hgetdel-variadic-fields"
        array_key = "hgetdel-array-fields"
        fields_and_values = %w[field1 value1 field2 value2]
        client.hset(variadic_key, *fields_and_values)
        client.hset(array_key, *fields_and_values)

        variadic_result = client.hgetdel(variadic_key, "field1", "field2")
        array_result = client.hgetdel(array_key, %w[field1 field2])

        assert_equal %w[value1 value2], variadic_result
        assert_equal variadic_result, array_result
        assert_equal [nil, nil], client.hmget(variadic_key, "field1", "field2")
        assert_equal [nil, nil], client.hmget(array_key, "field1", "field2")
      end
    ensure
      client&.close
    end

    parameterized_test(
      :test_hgetdel_existing_and_missing_fields,
      protocol: %i[resp2 resp3]
    ) do |protocol|
      client = nil
      target_version "9.1" do
        client = _new_client(protocol: protocol)
        key = "hgetdel-existing-and-missing"
        client.hset(key, "field1", "value1", "field2", "value2")

        result = client.hgetdel(key, "field1", "missing", "field2")

        assert_equal ["value1", nil, "value2"], result
        assert_equal [nil, nil], client.hmget(key, "field1", "field2")
      end
    ensure
      client&.close
    end

    parameterized_test(
      :test_hgetdel_removes_empty_hash_key,
      protocol: %i[resp2 resp3]
    ) do |protocol|
      client = nil
      target_version "9.1" do
        client = _new_client(protocol: protocol)
        key = "hgetdel-removes-empty-hash"
        client.hset(key, "field1", "value1", "field2", "value2")

        assert_equal %w[value1 value2], client.hgetdel(key, "field1", "field2")
        assert_equal false, client.exists?(key)
      end
    ensure
      client&.close
    end

    parameterized_test(
      :test_hgetdel_missing_key,
      protocol: %i[resp2 resp3]
    ) do |protocol|
      client = nil
      target_version "9.1" do
        client = _new_client(protocol: protocol)

        assert_equal [nil, nil], client.hgetdel("hgetdel-missing-key", "field1", "field2")
      end
    ensure
      client&.close
    end

    parameterized_test(
      :test_hgetdel_wrong_type,
      protocol: %i[resp2 resp3]
    ) do |protocol|
      client = nil
      target_version "9.1" do
        client = _new_client(protocol: protocol)
        key = "hgetdel-wrong-type"
        client.set(key, "value")

        error = assert_raises(Valkey::CommandError) { client.hgetdel(key, "field") }

        assert_includes error.message, "WRONGTYPE"
      end
    ensure
      client&.close
    end

    parameterized_test(
      :test_hgetdel_empty_fields,
      protocol: %i[resp2 resp3]
    ) do |protocol|
      client = nil
      target_version "9.1" do
        client = _new_client(protocol: protocol)

        error = assert_raises(Valkey::CommandError) { client.hgetdel("hgetdel-empty-fields") }

        # Valkey rejects FIELDS 0 at command arity validation before checking numfields.
        assert_includes error.message, "wrong number of arguments"
      end
    ensure
      client&.close
    end

    parameterized_test(
      :test_hgetdel_in_pipeline,
      protocol: %i[resp2 resp3]
    ) do |protocol|
      client = nil
      target_version "9.1" do
        client = _new_client(protocol: protocol)
        key = "hgetdel-pipeline"
        client.hset(key, "field", "value")
        future = nil

        results = client.pipelined do |pipeline|
          future = pipeline.hgetdel(key, "field", "missing")
        end

        assert_equal [["value", nil]], results
        assert_equal ["value", nil], future.value
        assert_nil client.hget(key, "field")
      end
    ensure
      client&.close
    end

    def test_hset_and_hget
      r.hset("foo", "f1", "s1")

      assert_equal "s1", r.hget("foo", "f1")
    end

    def test_hset_with_hash
      r.hset("foo", { "f1" => "s1", "f2" => "s2" })

      assert_equal "s1", r.hget("foo", "f1")
      assert_equal "s2", r.hget("foo", "f2")
    end

    def test_hset_with_multiple_args
      assert_equal 2, r.hset("foo", "f1", "s1", "f2", "s2")
      assert_equal "s1", r.hget("foo", "f1")
      assert_equal "s2", r.hget("foo", "f2")
    end

    def test_hsetnx
      r.hset("foo", "f1", "s1")
      assert_equal false, r.hsetnx("foo", "f1", "s2")
      assert_equal "s1", r.hget("foo", "f1")

      r.del("foo")
      assert_equal true, r.hsetnx("foo", "f1", "s2")
      assert_equal "s2", r.hget("foo", "f1")
    end

    def test_hdel
      r.hset("foo", "f1", "s1")
      r.hset("foo", "f2", "s2")

      assert_equal 1, r.hdel("foo", "f1")
      assert_nil r.hget("foo", "f1")
      assert_equal "s2", r.hget("foo", "f2")
    end

    def test_array_hdel
      r.hset("foo", "f1", "s1")
      r.hset("foo", "f2", "s2")
      r.hset("foo", "f3", "s3")

      assert_equal 2, r.hdel("foo", %w[f1 f2])
      assert_nil r.hget("foo", "f1")
      assert_nil r.hget("foo", "f2")
      assert_equal "s3", r.hget("foo", "f3")
    end

    def test_splat_hdel
      r.hset("foo", "f1", "s1")
      r.hset("foo", "f2", "s2")
      r.hset("foo", "f3", "s3")

      assert_equal 2, r.hdel("foo", "f1", "f2")
      assert_nil r.hget("foo", "f1")
      assert_nil r.hget("foo", "f2")
      assert_equal "s3", r.hget("foo", "f3")
    end

    def test_hexists
      r.hset("foo", "f1", "s1")

      assert r.hexists("foo", "f1")
      assert !r.hexists("foo", "f2")
    end

    def test_hlen
      assert_equal 0, r.hlen("foo")

      r.hset("foo", "f1", "s1")
      assert_equal 1, r.hlen("foo")

      r.hset("foo", "f2", "s2")
      assert_equal 2, r.hlen("foo")
    end

    def test_hkeys
      r.hset("foo", "f1", "s1")
      r.hset("foo", "f2", "s2")

      assert_equal %w[f1 f2], r.hkeys("foo").sort
    end

    def test_hvals
      r.hset("foo", "f1", "s1")
      r.hset("foo", "f2", "s2")

      assert_equal %w[s1 s2], r.hvals("foo").sort
    end

    def test_hgetall
      r.hset("foo", "f1", "s1")
      r.hset("foo", "f2", "s2")

      assert_equal({ "f1" => "s1", "f2" => "s2" }, r.hgetall("foo"))
    end

    def test_hmget
      r.hset("foo", "f1", "s1")
      r.hset("foo", "f2", "s2")
      r.hset("foo", "f3", "s3")

      assert_equal %w[s1 s2], r.hmget("foo", "f1", "f2")
      assert_equal ["s1", "s2", nil], r.hmget("foo", "f1", "f2", "f4")
    end

    def test_mapped_hmget
      r.hset("foo", "f1", "s1")
      r.hset("foo", "f2", "s2")

      response = r.mapped_hmget("foo", "f1", "f2")

      assert_equal "s1", response["f1"]
      assert_equal "s2", response["f2"]

      response = r.mapped_hmget("foo", "f1", "f2", "f3")

      assert_equal "s1", response["f1"]
      assert_equal "s2", response["f2"]
      assert_nil response["f3"]
    end

    def test_hmset
      r.hmset("foo", "f1", "s1", "f2", "s2")

      assert_equal "s1", r.hget("foo", "f1")
      assert_equal "s2", r.hget("foo", "f2")
    end

    def test_mapped_hmset
      r.mapped_hmset("foo", { "f1" => "s1", "f2" => "s2" })

      assert_equal "s1", r.hget("foo", "f1")
      assert_equal "s2", r.hget("foo", "f2")
    end

    def test_hincrby
      assert_equal 1, r.hincrby("foo", "f1", 1)
      assert_equal 3, r.hincrby("foo", "f1", 2)
      assert_equal 0, r.hincrby("foo", "f1", -3)
    end

    def test_hincrbyfloat
      assert_equal 1.23, r.hincrbyfloat("foo", "f1", 1.23)
      assert_equal 2.0, r.hincrbyfloat("foo", "f1", 0.77)
      assert_equal 1.9, r.hincrbyfloat("foo", "f1", -0.1)
    end

    def test_hstrlen
      r.hset("foo", "f1", "lorem")

      assert_equal 5, r.hstrlen("foo", "f1")
      assert_equal 0, r.hstrlen("foo", "f2")
    end

    def test_hrandfield
      r.hset("foo", "f1", "s1")
      r.hset("foo", "f2", "s2")
      r.hset("foo", "f3", "s3")

      field = r.hrandfield("foo")
      assert %w[f1 f2 f3].include?(field)

      fields = r.hrandfield("foo", 2)
      assert_equal 2, fields.size
      assert(fields.all? { |f| %w[f1 f2 f3].include?(f) })
    end

    def test_hrandfield_with_withvalues
      r.hset("foo", "f1", "s1")
      r.hset("foo", "f2", "s2")

      result = r.hrandfield("foo", 1, with_values: true)
      assert_equal 1, result.size
      assert result[0].is_a?(Array)
      assert_equal 2, result[0].size
      assert %w[f1 f2].include?(result[0][0])
      assert %w[s1 s2].include?(result[0][1])
    end

    def test_hrandfield_with_withvalues_alias
      r.hset("foo", "f1", "s1")
      r.hset("foo", "f2", "s2")

      result = r.hrandfield("foo", 1, withvalues: true)
      assert_equal 1, result.size
      assert result[0].is_a?(Array)
    end

    def test_hrandfield_with_withvalues_requires_count
      assert_raises(ArgumentError) do
        r.hrandfield("foo", with_values: true)
      end
    end

    def test_hscan
      r.hset("foo", "f1", "s1")
      r.hset("foo", "f2", "s2")
      r.hset("foo", "f3", "s3")

      cursor, pairs = r.hscan("foo", 0)
      assert cursor.is_a?(String)
      assert pairs.is_a?(Array)
      assert pairs.size >= 3 # at least 3 field-value pairs
      assert(pairs.all? { |pair| pair.is_a?(Array) && pair.size == 2 })
    end

    def test_hscan_with_match
      r.hset("foo", "f1", "s1")
      r.hset("foo", "f2", "s2")
      r.hset("foo", "f3", "s3")

      cursor, pairs = r.hscan("foo", 0, match: "f1")
      assert cursor.is_a?(String)
      assert pairs.is_a?(Array)
      assert(pairs.all? { |pair| pair.is_a?(Array) && pair.size == 2 })
    end

    def test_hscan_with_count
      r.hset("foo", "f1", "s1")
      r.hset("foo", "f2", "s2")
      r.hset("foo", "f3", "s3")

      cursor, pairs = r.hscan("foo", 0, count: 2)
      assert cursor.is_a?(String)
      assert pairs.is_a?(Array)
      assert(pairs.all? { |pair| pair.is_a?(Array) && pair.size == 2 })
    end

    def test_hscan_each
      r.hset("foo", "f1", "s1")
      r.hset("foo", "f2", "s2")
      r.hset("foo", "f3", "s3")

      results = []
      r.hscan_each("foo") do |field, value|
        results << [field, value]
      end

      assert results.size >= 3
      assert(results.any? { |f, v| f == "f1" && v == "s1" })
    end

    def test_hsetex
      target_version "9.0" do
        r.hsetex("foo", "f1", "s1", 2)
        assert_equal "s1", r.hget("foo", "f1")
        assert_in_range 0..2, r.httl("foo", "f1").first
      end
    end

    def test_hgetex
      target_version "9.0" do
        r.hset("foo", "f1", "s1")
        assert_equal "s1", r.hgetex("foo", "f1", ex: 2)
        assert_in_range 0..2, r.httl("foo", "f1").first
      end
    end

    def test_hgetex_multiple_fields
      target_version "9.0" do
        r.hset("foo", "f1", "s1", "f2", "s2")
        values = r.hgetex("foo", "f1", "f2", ex: 2)
        assert_equal %w[s1 s2], values
      end
    end

    def test_hgetex_with_persist
      target_version "9.0" do
        r.hsetex("foo", "f1", "s1", 100)
        assert_equal "s1", r.hgetex("foo", "f1", persist: true)
        assert_equal([-1], r.httl("foo", "f1"))
      end
    end

    def test_hexpire
      target_version "9.0" do
        r.hset("foo", "f1", "s1")
        assert_equal [1], r.hexpire("foo", 2, "f1")
        assert_in_range 0..2, r.httl("foo", "f1").first
      end
    end

    def test_hexpire_multiple_fields
      target_version "9.0" do
        r.hset("foo", "f1", "s1", "f2", "s2")
        results = r.hexpire("foo", 2, "f1", "f2")
        assert_equal [1, 1], results
      end
    end

    def test_hexpire_with_options
      target_version "9.0" do
        r.hset("foo", "f1", "s1")
        assert_equal [1], r.hexpire("foo", 10, "f1")
        assert_equal [1], r.hexpire("foo", 5, "f1", lt: true)
        assert_in_range 0..5, r.httl("foo", "f1").first
      end
    end

    def test_hexpireat
      target_version "9.0" do
        r.hset("foo", "f1", "s1")
        assert_equal [1], r.hexpireat("foo", Time.now.to_i + 2, "f1")
        assert_in_range 0..2, r.httl("foo", "f1").first
      end
    end

    def test_hpexpire
      target_version "9.0" do
        r.hset("foo", "f1", "s1")
        assert_equal [1], r.hpexpire("foo", 2000, "f1")
        assert_in_range 0..2, r.httl("foo", "f1").first
      end
    end

    def test_hpexpireat
      target_version "9.0" do
        r.hset("foo", "f1", "s1")
        assert_equal [1], r.hpexpireat("foo", (Time.now.to_i * 1000) + 2000, "f1")
        assert_in_range 0..2, r.httl("foo", "f1").first
      end
    end

    def test_hpersist
      target_version "9.0" do
        r.hsetex("foo", "f1", "s1", 100)
        assert_equal [1], r.hpersist("foo", "f1")
        assert_equal([-1], r.httl("foo", "f1"))
      end
    end

    def test_hpersist_multiple_fields
      target_version "9.0" do
        r.hsetex("foo", "f1", "s1", 100)
        r.hsetex("foo", "f2", "s2", 100)
        results = r.hpersist("foo", "f1", "f2")
        assert_equal [1, 1], results
      end
    end

    def test_httl
      target_version "9.0" do
        r.hset("foo", "f1", "s1")
        assert_equal([-1], r.httl("foo", "f1"))

        r.hsetex("foo", "f1", "s1", 2)
        assert_in_range 0..2, r.httl("foo", "f1").first

        assert_equal([-2], r.httl("foo", "f2"))
      end
    end

    def test_httl_multiple_fields
      target_version "9.0" do
        r.hset("foo", "f1", "s1", "f2", "s2")
        r.hsetex("foo", "f1", "s1", 2)
        results = r.httl("foo", "f1", "f2", "f3")
        assert results[0].between?(0, 2)
        assert_equal(-1, results[1])
        assert_equal(-2, results[2])
      end
    end

    def test_hpttl
      target_version "9.0" do
        r.hset("foo", "f1", "s1")
        assert_equal([-1], r.hpttl("foo", "f1"))

        r.hpexpire("foo", 2000, "f1")
        assert_in_range 0..2000, r.hpttl("foo", "f1").first

        assert_equal([-2], r.hpttl("foo", "f2"))
      end
    end

    def test_hexpiretime
      target_version "9.0" do
        r.hset("foo", "f1", "s1")
        assert_equal([-1], r.hexpiretime("foo", "f1"))

        expire_time = Time.now.to_i + 100
        r.hexpireat("foo", expire_time, "f1")
        assert_in_range (expire_time - 1)..(expire_time + 1), r.hexpiretime("foo", "f1").first

        assert_equal([-2], r.hexpiretime("foo", "f2"))
      end
    end

    def test_hpexpiretime
      target_version "9.0" do
        r.hset("foo", "f1", "s1")
        assert_equal([-1], r.hpexpiretime("foo", "f1"))

        expire_time = (Time.now.to_i * 1000) + 100_000
        r.hpexpireat("foo", expire_time, "f1")
        assert_in_range (expire_time - 1000)..(expire_time + 1000), r.hpexpiretime("foo", "f1").first

        assert_equal([-2], r.hpexpiretime("foo", "f2"))
      end
    end
  end
end
