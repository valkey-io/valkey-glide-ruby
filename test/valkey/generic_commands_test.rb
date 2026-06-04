# frozen_string_literal: true

module ValkeyTests
  module GenericCommands
    def test_randomkey
      # This test expects an empty database at start, which isn't guaranteed
      # in cluster mode where tests share the same cluster instance
      skip("Requires isolated database") if cluster_mode?

      assert r.randomkey.to_s.empty?

      r.set("foo", "s1")

      assert_equal "foo", r.randomkey

      r.set("bar", "s2")

      4.times do
        assert %w[foo bar].include?(r.randomkey)
      end
    end
  end
end
