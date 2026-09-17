# frozen_string_literal: true

module Lint
  module PubSubCommands
    def test_publish
      result = r.publish("Hello, World!", "lint_pubsub_no_subscribers")

      assert_equal 0, result
    end

    def test_pubsub_channels
      # List all active channels
      channels = r.pubsub_channels

      assert_kind_of Array, channels
      channels.each { |channel| assert_kind_of String, channel }
    end

    def test_pubsub_channels_with_pattern
      # List channels matching a pattern
      channels = r.pubsub_channels("test*")

      assert_kind_of Array, channels
      channels.each { |channel| assert_kind_of String, channel }
    end

    def test_pubsub_numpat
      # Get number of pattern subscriptions
      count = r.pubsub_numpat

      assert_kind_of Integer, count
      assert count >= 0
    end

    def test_pubsub_numsub
      result = r.pubsub_numsub("lint_numsub_chan1", "lint_numsub_chan2")

      assert_numsub({ "lint_numsub_chan1" => 0, "lint_numsub_chan2" => 0 }, result)
    end

    def test_pubsub_numsub_no_channels
      result = r.pubsub_numsub

      assert_numsub({}, result)
    end

    def test_pubsub_shardchannels
      # PUBSUB SHARDCHANNELS was introduced in Redis 7.0.
      # Skipped on Redis 6.2 and earlier versions.
      omit_version("7.0")
      # List all active shard channels
      channels = r.pubsub_shardchannels

      assert_kind_of Array, channels
      channels.each { |channel| assert_kind_of String, channel }
    rescue Valkey::TimeoutError
      skip("Shard channel command timed out - cluster may be initializing")
    rescue Valkey::CommandError => e
      skip("Shard channels not supported") if e.message.include?("unknown command")
      raise
    end

    def test_pubsub_shardchannels_with_pattern
      # PUBSUB SHARDCHANNELS was introduced in Redis 7.0.
      # Skipped on Redis 6.2 and earlier versions.
      omit_version("7.0")
      # List shard channels matching a pattern
      channels = r.pubsub_shardchannels("shard*")

      assert_kind_of Array, channels
      channels.each { |channel| assert_kind_of String, channel }
    rescue Valkey::TimeoutError
      skip("Shard channel command timed out - cluster may be initializing")
    rescue Valkey::CommandError => e
      skip("Shard channels not supported") if e.message.include?("unknown command")
      raise
    end

    def test_pubsub_shardnumsub
      # PUBSUB SHARDNUMSUB was introduced in Redis 7.0.
      # Skipped on Redis 6.2 and earlier versions.
      omit_version("7.0")
      result = r.pubsub_shardnumsub("lint_shard_chan1", "lint_shard_chan2")

      assert_numsub({ "lint_shard_chan1" => 0, "lint_shard_chan2" => 0 }, result)
    rescue Valkey::TimeoutError
      skip("Shard channel command timed out - cluster may be initializing")
    rescue Valkey::CommandError => e
      skip("Shard channels not supported") if e.message.include?("unknown command")
      raise
    end

    def test_spublish
      # SPUBLISH was introduced in Redis 7.0.
      # Skipped on Redis 6.2 and earlier versions.
      omit_version("7.0")
      result = r.publish("Hello, Shard!", "lint_shard_no_subscribers", sharded: true)

      assert_equal 0, result
    rescue NotImplementedError
      skip("sharded publish is not implemented yet (Part 4)")
    rescue Valkey::TimeoutError
      # In some cluster configurations, shard channels may timeout
      # This can happen if the cluster is still initializing or routing is not ready
      skip("Shard channel publish timed out - cluster may be initializing")
    rescue Valkey::CommandError => e
      # Skip if shard channels not supported
      skip("Shard channels not supported") if e.message.include?("unknown command") || e.message.include?("SPUBLISH")
      raise
    end
  end
end
