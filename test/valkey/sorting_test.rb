# frozen_string_literal: true

module ValkeyTests
  module Sorting
    def test_sort
      # SORT with GET uses multiple keys that may hash to different slots
      skip("CrossSlot operation not supported in cluster mode") if cluster_mode?

      r.set("foo:1", "s1")
      r.set("foo:2", "s2")

      r.rpush("bar", "1")
      r.rpush("bar", "2")

      assert_equal ["s1"], r.sort("bar", get: "foo:*", limit: [0, 1])
      assert_equal ["s2"], r.sort("bar", get: "foo:*", limit: [0, 1], order: "desc alpha")
    end

    def test_sort_with_an_array_of_gets
      # SORT with GET uses multiple keys that may hash to different slots
      skip("CrossSlot operation not supported in cluster mode") if cluster_mode?

      r.set("foo:1:a", "s1a")
      r.set("foo:1:b", "s1b")

      r.set("foo:2:a", "s2a")
      r.set("foo:2:b", "s2b")

      r.rpush("bar", "1")
      r.rpush("bar", "2")

      assert_equal [%w[s1a s1b]], r.sort("bar", get: ["foo:*:a", "foo:*:b"], limit: [0, 1])
      assert_equal [%w[s2a s2b]], r.sort("bar", get: ["foo:*:a", "foo:*:b"], limit: [0, 1], order: "desc alpha")
      assert_equal [%w[s1a s1b], %w[s2a s2b]], r.sort("bar", get: ["foo:*:a", "foo:*:b"])
    end

    def test_sort_with_store
      # SORT with STORE uses multiple keys that may hash to different slots
      skip("CrossSlot operation not supported in cluster mode") if cluster_mode?

      r.set("foo:1", "s1")
      r.set("foo:2", "s2")

      r.rpush("bar", "1")
      r.rpush("bar", "2")

      r.sort("bar", get: "foo:*", store: "baz")
      assert_equal %w[s1 s2], r.lrange("baz", 0, -1)
    end

    def test_sort_with_an_array_of_gets_and_with_store
      # SORT with GET and STORE uses multiple keys that may hash to different slots
      skip("CrossSlot operation not supported in cluster mode") if cluster_mode?

      r.set("foo:1:a", "s1a")
      r.set("foo:1:b", "s1b")

      r.set("foo:2:a", "s2a")
      r.set("foo:2:b", "s2b")

      r.rpush("bar", "1")
      r.rpush("bar", "2")

      r.sort("bar", get: ["foo:*:a", "foo:*:b"], store: 'baz')
      assert_equal %w[s1a s1b s2a s2b], r.lrange("baz", 0, -1)
    end
  end
end
