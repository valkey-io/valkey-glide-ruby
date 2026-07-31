# frozen_string_literal: true

require "test_helper"

# Regression tests for xtrim behavior:
#   1. Default approximate is now `false` so xtrim(k, N) trims to exactly N.
#   2. LIMIT modifier is supported when approximate: true.
#   3. LIMIT without approximate: true raises ArgumentError.
#   4. MINID strategy still works.
#
# Server: 127.0.0.1:8101 (dedicated port for this regression suite).
class TestXtrimRegression < Minitest::Test
  SERVER_HOST = "127.0.0.1"
  SERVER_PORT = 8101

  def setup
    @r = Valkey.new(host: SERVER_HOST, port: SERVER_PORT, timeout: 5.0)
    @key_prefix = "xtrim-regression-#{Process.pid}-#{object_id}"
    @keys = []
  end

  def teardown
    @keys.each { |k| @r.del(k) }
    @r.close
  end

  def unique_key(name)
    key = "#{@key_prefix}-#{name}"
    @keys << key
    @r.del(key)
    key
  end

  def add_entries(key, count)
    ids = []
    count.times do |i|
      ids << @r.xadd(key, { "field" => "value#{i}" })
    end
    ids
  end

  def test_xtrim_default_trims_exactly
    key = unique_key("default")
    add_entries(key, 10)
    assert_equal 10, @r.xlen(key)

    removed = @r.xtrim(key, 5)
    assert_equal 5, removed
    assert_equal 5, @r.xlen(key)
  end

  def test_xtrim_explicit_approximate_false
    key = unique_key("explicit-exact")
    add_entries(key, 10)
    assert_equal 10, @r.xlen(key)

    removed = @r.xtrim(key, 5, approximate: false)
    assert_equal 5, removed
    assert_equal 5, @r.xlen(key)
  end

  def test_xtrim_explicit_maxlen_strategy
    key = unique_key("explicit-maxlen")
    add_entries(key, 10)
    assert_equal 10, @r.xlen(key)

    removed = @r.xtrim(key, 5, strategy: "MAXLEN")
    assert_equal 5, removed
    assert_equal 5, @r.xlen(key)
  end

  def test_xtrim_to_zero_removes_all
    key = unique_key("zero")
    add_entries(key, 10)
    assert_equal 10, @r.xlen(key)

    removed = @r.xtrim(key, 0)
    assert_equal 10, removed
    assert_equal 0, @r.xlen(key)
  end

  def test_xtrim_with_limit_and_approximate
    key = unique_key("limit")
    add_entries(key, 500)
    assert_equal 500, @r.xlen(key)

    # LIMIT is only allowed with approximate trimming. The exact number of entries
    # removed is server-dependent (radix-tree granularity), but the call must succeed
    # and return a non-negative Integer.
    removed = @r.xtrim(key, 5, approximate: true, limit: 100)
    assert_kind_of Integer, removed
    assert_operator removed, :>=, 0
  end

  def test_xtrim_with_limit_without_approximate_raises
    key = unique_key("limit-no-approx")
    add_entries(key, 10)

    error = assert_raises(ArgumentError) do
      @r.xtrim(key, 5, limit: 100)
    end
    assert_equal "LIMIT can only be used with approximate: true", error.message
  end

  def test_xtrim_minid_strategy
    key = unique_key("minid")
    ids = add_entries(key, 10)
    threshold = ids[4] # 5th entry - keep entries with id >= ids[4]
    assert_equal 10, @r.xlen(key)

    removed = @r.xtrim(key, threshold, strategy: "MINID")
    assert_equal 4, removed
    assert_equal 6, @r.xlen(key)
  end
end
