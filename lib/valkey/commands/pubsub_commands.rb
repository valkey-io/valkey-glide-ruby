# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands related to Valkey Pub/Sub.
    #
    # @see https://valkey.io/commands/#pubsub
    #
    module PubSubCommands
      # Subscribe to one or more channels.
      #
      # @example Subscribe to channels
      #   valkey.subscribe("channel1", "channel2")
      #     # => "OK"
      #
      # @param [Array<String>] channels the channels to subscribe to
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/subscribe/
      def subscribe(*channels)
        send_command(RequestType::SUBSCRIBE, channels)
      end

      # Unsubscribe from one or more channels.
      #
      # @example Unsubscribe from channels
      #   valkey.unsubscribe("channel1", "channel2")
      #     # => "OK"
      # @example Unsubscribe from all channels
      #   valkey.unsubscribe
      #     # => "OK"
      #
      # @param [Array<String>] channels the channels to unsubscribe from (empty for all)
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/unsubscribe/
      def unsubscribe(*channels)
        send_command(RequestType::UNSUBSCRIBE, channels)
      end

      # Subscribe to one or more patterns.
      #
      # @example Subscribe to patterns
      #   valkey.psubscribe("news.*", "events.*")
      #     # => "OK"
      #
      # @param [Array<String>] patterns the patterns to subscribe to
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/psubscribe/
      def psubscribe(*patterns)
        send_command(RequestType::PSUBSCRIBE, patterns)
      end

      # Unsubscribe from one or more patterns.
      #
      # @example Unsubscribe from patterns
      #   valkey.punsubscribe("news.*", "events.*")
      #     # => "OK"
      # @example Unsubscribe from all patterns
      #   valkey.punsubscribe
      #     # => "OK"
      #
      # @param [Array<String>] patterns the patterns to unsubscribe from (empty for all)
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/punsubscribe/
      def punsubscribe(*patterns)
        send_command(RequestType::PUNSUBSCRIBE, patterns)
      end

      # Publish a message to a channel.
      #
      # @example Publish a message
      #   valkey.publish("channel1", "Hello, World!")
      #     # => 2
      #
      # @param [String] channel the channel to publish to
      # @param [String] message the message to publish
      # @return [Integer] the number of clients that received the message
      #
      # @see https://valkey.io/commands/publish/
      def publish(channel, message)
        send_command(RequestType::PUBLISH, [channel, message])
      end

      # Subscribe to one or more shard channels.
      #
      # @example Subscribe to shard channels
      #   valkey.ssubscribe("shard1", "shard2")
      #     # => "OK"
      #
      # @param [Array<String>] channels the shard channels to subscribe to
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/ssubscribe/
      def ssubscribe(*channels)
        send_command(RequestType::SSUBSCRIBE, channels)
      end

      # Unsubscribe from one or more shard channels.
      #
      # @example Unsubscribe from shard channels
      #   valkey.sunsubscribe("shard1", "shard2")
      #     # => "OK"
      # @example Unsubscribe from all shard channels
      #   valkey.sunsubscribe
      #     # => "OK"
      #
      # @param [Array<String>] channels the shard channels to unsubscribe from (empty for all)
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/sunsubscribe/
      def sunsubscribe(*channels)
        send_command(RequestType::SUNSUBSCRIBE, channels)
      end

      # Publish a message to a shard channel.
      #
      # @example Publish a message to a shard channel
      #   valkey.spublish("shard1", "Hello, Shard!")
      #     # => 1
      #
      # @param [String] channel the shard channel to publish to
      # @param [String] message the message to publish
      # @return [Integer] the number of clients that received the message
      #
      # @see https://valkey.io/commands/spublish/
      def spublish(channel, message)
        send_command(RequestType::SPUBLISH, [channel, message])
      end

      # List active channels.
      #
      # @example List all active channels
      #   valkey.pubsub_channels
      #     # => ["channel1", "channel2"]
      # @example List active channels matching a pattern
      #   valkey.pubsub_channels("news.*")
      #     # => ["news.sports", "news.tech"]
      #
      # @param [String] pattern optional pattern to filter channels
      # @return [Array<String>] list of active channels
      #
      # @see https://valkey.io/commands/pubsub-channels/
      def pubsub_channels(pattern = nil)
        args = pattern ? [pattern] : []
        send_command(RequestType::PUBSUB_CHANNELS, args)
      end

      # Get the number of unique patterns subscribed to.
      #
      # @example Get pattern count
      #   valkey.pubsub_numpat
      #     # => 3
      #
      # @return [Integer] the number of patterns
      #
      # @see https://valkey.io/commands/pubsub-numpat/
      def pubsub_numpat
        send_command(RequestType::PUBSUB_NUM_PAT)
      end

      # Get the number of subscribers for channels.
      #
      # @example Get subscriber counts
      #   valkey.pubsub_numsub("channel1", "channel2")
      #     # => ["channel1", 5, "channel2", 3]
      #
      # @param [Array<String>] channels the channels to check
      # @return [Array] channel names and subscriber counts
      #
      # @see https://valkey.io/commands/pubsub-numsub/
      def pubsub_numsub(*channels)
        send_command(RequestType::PUBSUB_NUM_SUB, channels)
      end

      # List active shard channels.
      #
      # @example List all active shard channels
      #   valkey.pubsub_shardchannels
      #     # => ["shard1", "shard2"]
      # @example List active shard channels matching a pattern
      #   valkey.pubsub_shardchannels("shard.*")
      #     # => ["shard.1", "shard.2"]
      #
      # @param [String] pattern optional pattern to filter shard channels
      # @return [Array<String>] list of active shard channels
      #
      # @see https://valkey.io/commands/pubsub-shardchannels/
      def pubsub_shardchannels(pattern = nil)
        args = pattern ? [pattern] : []
        send_command(RequestType::PUBSUB_SHARD_CHANNELS, args)
      end

      # Get the number of subscribers for shard channels.
      #
      # @example Get shard subscriber counts
      #   valkey.pubsub_shardnumsub("shard1", "shard2")
      #     # => ["shard1", 2, "shard2", 1]
      #
      # @param [Array<String>] channels the shard channels to check
      # @return [Array] shard channel names and subscriber counts
      #
      # @see https://valkey.io/commands/pubsub-shardnumsub/
      def pubsub_shardnumsub(*channels)
        send_command(RequestType::PUBSUB_SHARD_NUM_SUB, channels)
      end

      # Control pub/sub operations (convenience method).
      #
      # @example List active channels
      #   valkey.pubsub(:channels)
      #     # => ["channel1", "channel2"]
      # @example Get pattern count
      #   valkey.pubsub(:numpat)
      #     # => 3
      # @example Get subscriber counts
      #   valkey.pubsub(:numsub, "channel1", "channel2")
      #     # => ["channel1", 5, "channel2", 3]
      # @example List active shard channels
      #   valkey.pubsub(:shardchannels)
      #     # => ["shard1", "shard2"]
      # @example Get shard subscriber counts
      #   valkey.pubsub(:shardnumsub, "shard1", "shard2")
      #     # => ["shard1", 2, "shard2", 1]
      #
      # @param [String, Symbol] subcommand the subcommand (channels, numpat, numsub, shardchannels, shardnumsub)
      # @param [Array] args arguments for the subcommand
      # @return [Object] depends on subcommand
      def pubsub(subcommand, *args)
        subcommand = subcommand.to_s.downcase
        send("pubsub_#{subcommand}", *args)
      end
    end
  end
end
