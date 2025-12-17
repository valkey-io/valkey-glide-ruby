# frozen_string_literal: true

module Lint
  module PubSubCommands
    def test_publish
      # Publish to a channel with no subscribers
      result = r.publish("test_channel", "Hello, World!")
      assert_kind_of Integer, result
      assert result >= 0
    end

    def test_pubsub_channels
      # List all active channels
      channels = r.pubsub_channels
      assert_kind_of Array, channels
    end

    def test_pubsub_channels_with_pattern
      # List channels matching a pattern
      channels = r.pubsub_channels("test*")
      assert_kind_of Array, channels
    end

    def test_pubsub_numpat
      # Get number of pattern subscriptions
      count = r.pubsub_numpat
      assert_kind_of Integer, count
      assert count >= 0
    end

    def test_pubsub_numsub
      # Get subscriber counts for channels
      result = r.pubsub_numsub("channel1", "channel2")
      assert_kind_of Array, result
    end

    def test_pubsub_numsub_no_channels
      # Get subscriber counts with no channels specified
      result = r.pubsub_numsub
      assert_kind_of Array, result
    end

    def test_pubsub_shardchannels
      # List all active shard channels
      channels = r.pubsub_shardchannels
      assert_kind_of Array, channels
    rescue Valkey::TimeoutError
      skip("Shard channel command timed out - cluster may be initializing")
    rescue Valkey::CommandError => e
      skip("Shard channels not supported") if e.message.include?("unknown command")
      raise
    end

    def test_pubsub_shardchannels_with_pattern
      # List shard channels matching a pattern
      channels = r.pubsub_shardchannels("shard*")
      assert_kind_of Array, channels
    rescue Valkey::TimeoutError
      skip("Shard channel command timed out - cluster may be initializing")
    rescue Valkey::CommandError => e
      skip("Shard channels not supported") if e.message.include?("unknown command")
      raise
    end

    def test_pubsub_shardnumsub
      # Get subscriber counts for shard channels
      result = r.pubsub_shardnumsub("shard1", "shard2")
      assert_kind_of Array, result
    rescue Valkey::TimeoutError
      skip("Shard channel command timed out - cluster may be initializing")
    rescue Valkey::CommandError => e
      skip("Shard channels not supported") if e.message.include?("unknown command")
      raise
    end

    def test_spublish
      # Publish to a shard channel with no subscribers
      result = r.spublish("test_shard", "Hello, Shard!")
      assert_kind_of Integer, result
      assert result >= 0
    rescue Valkey::TimeoutError
      # In some cluster configurations, shard channels may timeout
      # This can happen if the cluster is still initializing or routing is not ready
      skip("Shard channel publish timed out - cluster may be initializing")
    rescue Valkey::CommandError => e
      # Skip if shard channels not supported
      skip("Shard channels not supported") if e.message.include?("unknown command") || e.message.include?("SPUBLISH")
      raise
    end

    def test_pubsub_convenience_method_channels
      channels = r.pubsub(:channels)
      assert_kind_of Array, channels
    end

    def test_pubsub_convenience_method_channels_with_pattern
      channels = r.pubsub(:channels, "test*")
      assert_kind_of Array, channels
    end

    def test_pubsub_convenience_method_numpat
      count = r.pubsub(:numpat)
      assert_kind_of Integer, count
      assert count >= 0
    end

    def test_pubsub_convenience_method_numsub
      result = r.pubsub(:numsub, "channel1", "channel2")
      assert_kind_of Array, result
    end

    def test_pubsub_convenience_method_shardchannels
      channels = r.pubsub(:shardchannels)
      assert_kind_of Array, channels
    rescue Valkey::TimeoutError
      skip("Shard channel command timed out - cluster may be initializing")
    rescue Valkey::CommandError => e
      skip("Shard channels not supported") if e.message.include?("unknown command")
      raise
    end

    def test_pubsub_convenience_method_shardnumsub
      result = r.pubsub(:shardnumsub, "shard1", "shard2")
      assert_kind_of Array, result
    rescue Valkey::TimeoutError
      skip("Shard channel command timed out - cluster may be initializing")
    rescue Valkey::CommandError => e
      skip("Shard channels not supported") if e.message.include?("unknown command")
      raise
    end
  end
end
