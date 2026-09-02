# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands for Valkey Pub/Sub.
    #
    # Pub/Sub requires the RESP3 protocol. Subscriptions can be declared when the client is created, and are
    # applied via SUBSCRIBE/PSUBSCRIBE/SSUBSCRIBE during connection establishment:
    #
    #   valkey = Valkey.new(
    #     protocol: :resp3,
    #     pubsub: {
    #       subscriptions: {
    #         exact: ["news"],           # channel names
    #         pattern: ["news.*"],       # channel name patterns
    #         sharded: ["shard-chan"]    # sharded channels, cluster mode only
    #       }
    #     }
    #   )
    #
    # There are three ways to receive messages:
    #
    # * Inline: messages are queued on the connection and read with {#get_pubsub_message} or
    #   {#try_get_pubsub_message}.
    # * Callback: a `callback:` proc receives every message instead, along with an arbitrary `context:`.
    #   Not supported yet.
    # * Lazy: the `_lazy` subscribe and unsubscribe methods return without waiting for the server to confirm
    #   the change; read back {#get_subscriptions} to see the subscriptions the server actually has.
    #
    # @see https://valkey.io/docs/topics/pubsub/
    # @see https://valkey.io/commands/#pubsub
    #
    module PubSubCommands
      # Subscribe to exact channels, waiting for the server to confirm the subscription.
      #
      # @example Subscribe to channels
      #   valkey.subscribe("channel1", "channel2")
      # @example Give up if the server does not confirm within 2.5 seconds
      #   valkey.subscribe("channel1", timeout: 2.5)
      #
      # @param [Array<String>] channels the channels to subscribe to; an empty list is rejected
      # @param [Float, Integer, nil] timeout maximum time in seconds to wait for the server confirmation;
      #   `nil` blocks indefinitely
      # @return [void] returns once the server has confirmed the subscription
      # @raise [ArgumentError] if timeout is negative
      # @raise [Valkey::TimeoutError] if the timeout expires before the server confirms
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/subscribe/
      def subscribe(*channels, timeout: nil)
        @pubsub.subscribe(*channels, timeout: timeout)
      end

      # Unsubscribe from exact channels, waiting for the server to confirm the change.
      #
      # @example Unsubscribe from channels
      #   valkey.unsubscribe("channel1", "channel2")
      # @example Unsubscribe from every subscribed channel
      #   valkey.unsubscribe
      #
      # @param [Array<String>] channels the channels to unsubscribe from; an empty list unsubscribes from all
      #   exact channels
      # @param [Float, Integer, nil] timeout maximum time in seconds to wait for the server confirmation;
      #   `nil` blocks indefinitely
      # @return [void] returns once the server has confirmed the change
      # @raise [ArgumentError] if timeout is negative
      # @raise [Valkey::TimeoutError] if the timeout expires before the server confirms
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/unsubscribe/
      def unsubscribe(*channels, timeout: nil)
        @pubsub.unsubscribe(*channels, timeout: timeout)
      end

      # Subscribe to channel patterns, waiting for the server to confirm the subscription.
      #
      # @example Subscribe to patterns
      #   valkey.psubscribe("news.*", "events.*")
      # @example Give up if the server does not confirm within 1 second
      #   valkey.psubscribe("news.*", timeout: 1)
      #
      # @param [Array<String>] patterns the glob-style patterns to subscribe to; an empty list is rejected
      # @param [Float, Integer, nil] timeout maximum time in seconds to wait for the server confirmation;
      #   `nil` blocks indefinitely
      # @return [void] returns once the server has confirmed the subscription
      # @raise [ArgumentError] if timeout is negative
      # @raise [Valkey::TimeoutError] if the timeout expires before the server confirms
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/psubscribe/
      def psubscribe(*patterns, timeout: nil)
        @pubsub.psubscribe(*patterns, timeout: timeout)
      end

      # Unsubscribe from channel patterns, waiting for the server to confirm the change.
      #
      # @example Unsubscribe from patterns
      #   valkey.punsubscribe("news.*", "events.*")
      # @example Unsubscribe from every subscribed pattern
      #   valkey.punsubscribe
      #
      # @param [Array<String>] patterns the patterns to unsubscribe from; an empty list unsubscribes from all
      #   patterns
      # @param [Float, Integer, nil] timeout maximum time in seconds to wait for the server confirmation;
      #   `nil` blocks indefinitely
      # @return [void] returns once the server has confirmed the change
      # @raise [ArgumentError] if timeout is negative
      # @raise [Valkey::TimeoutError] if the timeout expires before the server confirms
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/punsubscribe/
      def punsubscribe(*patterns, timeout: nil)
        @pubsub.punsubscribe(*patterns, timeout: timeout)
      end

      # Subscribe to sharded channels, waiting for the server to confirm the subscription.
      #
      # Only available in cluster mode (`cluster_mode: true`). Since: Valkey version 7.0.0.
      #
      # @example Subscribe to shard channels
      #   valkey.ssubscribe("shard1", "shard2")
      # @example Give up if the server does not confirm within 2 seconds
      #   valkey.ssubscribe("shard1", timeout: 2)
      #
      # @param [Array<String>] channels the sharded channels to subscribe to; an empty list is rejected
      # @param [Float, Integer, nil] timeout maximum time in seconds to wait for the server confirmation;
      #   `nil` blocks indefinitely
      # @return [void] returns once the server has confirmed the subscription
      # @raise [ArgumentError] if timeout is negative
      # @raise [Valkey::TimeoutError] if the timeout expires before the server confirms
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/ssubscribe/
      def ssubscribe(*channels, timeout: nil)
        @pubsub.ssubscribe(*channels, timeout: timeout)
      end

      # Unsubscribe from sharded channels, waiting for the server to confirm the change.
      #
      # Only available in cluster mode (`cluster_mode: true`). Since: Valkey version 7.0.0.
      #
      # @example Unsubscribe from shard channels
      #   valkey.sunsubscribe("shard1", "shard2")
      # @example Unsubscribe from every subscribed shard channel
      #   valkey.sunsubscribe
      #
      # @param [Array<String>] channels the sharded channels to unsubscribe from; an empty list unsubscribes
      #   from all sharded channels
      # @param [Float, Integer, nil] timeout maximum time in seconds to wait for the server confirmation;
      #   `nil` blocks indefinitely
      # @return [void] returns once the server has confirmed the change
      # @raise [ArgumentError] if timeout is negative
      # @raise [Valkey::TimeoutError] if the timeout expires before the server confirms
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/sunsubscribe/
      def sunsubscribe(*channels, timeout: nil)
        @pubsub.sunsubscribe(*channels, timeout: timeout)
      end

      # Subscribe to exact channels without waiting for the server to confirm.
      #
      # The client subscribes asynchronously in the background.
      #
      # @example Subscribe and verify later
      #   valkey.subscribe_lazy("channel1", "channel2")
      #   valkey.get_subscriptions.actual_subscriptions[:exact]
      #     # => ["channel1", "channel2"]
      #
      # @param [Array<String>] channels the channels to subscribe to; an empty list is rejected
      # @return [void] returns as soon as the desired subscription state is updated
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/subscribe/
      def subscribe_lazy(*channels)
        @pubsub.subscribe_lazy(*channels)
      end

      # Unsubscribe from exact channels without waiting for the server to confirm.
      #
      # @example Unsubscribe and verify later
      #   valkey.unsubscribe_lazy("channel1")
      #   valkey.get_subscriptions.actual_subscriptions[:exact]
      #     # => ["channel2"]
      #
      # @param [Array<String>] channels the channels to unsubscribe from; an empty list unsubscribes from all
      #   exact channels
      # @return [void] returns as soon as the desired subscription state is updated
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/unsubscribe/
      def unsubscribe_lazy(*channels)
        @pubsub.unsubscribe_lazy(*channels)
      end

      # Subscribe to channel patterns without waiting for the server to confirm.
      #
      # The client subscribes asynchronously in the background.
      #
      # @example Subscribe and verify later
      #   valkey.psubscribe_lazy("news.*")
      #   valkey.get_subscriptions.actual_subscriptions[:pattern]
      #     # => ["news.*"]
      #
      # @param [Array<String>] patterns the glob-style patterns to subscribe to; an empty list is rejected
      # @return [void] returns as soon as the desired subscription state is updated
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/psubscribe/
      def psubscribe_lazy(*patterns)
        @pubsub.psubscribe_lazy(*patterns)
      end

      # Unsubscribe from channel patterns without waiting for the server to confirm.
      #
      # @example Unsubscribe and verify later
      #   valkey.punsubscribe_lazy("news.*")
      #   valkey.get_subscriptions.actual_subscriptions[:pattern]
      #     # => []
      #
      # @param [Array<String>] patterns the patterns to unsubscribe from; an empty list unsubscribes from all
      #   patterns
      # @return [void] returns as soon as the desired subscription state is updated
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/punsubscribe/
      def punsubscribe_lazy(*patterns)
        @pubsub.punsubscribe_lazy(*patterns)
      end

      # Subscribe to sharded channels without waiting for the server to confirm.
      #
      # The client subscribes asynchronously in the background. Only available in cluster mode
      # (`cluster_mode: true`). Since: Valkey version 7.0.0.
      #
      # @example Subscribe and verify later
      #   valkey.ssubscribe_lazy("shard1")
      #   valkey.get_subscriptions.actual_subscriptions[:sharded]
      #     # => ["shard1"]
      #
      # @param [Array<String>] channels the sharded channels to subscribe to; an empty list is rejected
      # @return [void] returns as soon as the desired subscription state is updated
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/ssubscribe/
      def ssubscribe_lazy(*channels)
        @pubsub.ssubscribe_lazy(*channels)
      end

      # Unsubscribe from sharded channels without waiting for the server to confirm.
      #
      # Only available in cluster mode (`cluster_mode: true`). Since: Valkey version 7.0.0.
      #
      # @example Unsubscribe and verify later
      #   valkey.sunsubscribe_lazy("shard1")
      #   valkey.get_subscriptions.actual_subscriptions[:sharded]
      #     # => []
      #
      # @param [Array<String>] channels the sharded channels to unsubscribe from; an empty list unsubscribes
      #   from all sharded channels
      # @return [void] returns as soon as the desired subscription state is updated
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/sunsubscribe/
      def sunsubscribe_lazy(*channels)
        @pubsub.sunsubscribe_lazy(*channels)
      end

      # Publish a message on a Pub/Sub channel.
      #
      # This method aggregates the PUBLISH and SPUBLISH functionalities; the mode is selected with the
      # `sharded` parameter. In both modes the request is routed using the hashed channel as key. The
      # argument order is `(message, channel)`, matching the other GLIDE clients.
      #
      # @example Publish a message
      #   valkey.publish("Hello, World!", "channel1")
      #     # => 2
      # @example Publish on a sharded channel
      #   valkey.publish("Hello, Shard!", "shard1", sharded: true)
      #     # => 1
      #
      # @param [String] message the message to publish
      # @param [String] channel the channel to publish the message on
      # @param [Boolean] sharded use sharded Pub/Sub mode; only available in cluster mode
      #   (`cluster_mode: true`). Since: Valkey version 7.0.0
      # @return [Integer] the number of subscriptions that received the message: in cluster mode the
      #   subscriptions on the node the request was routed to, in standalone the subscriptions on the primary
      #   node, which excludes subscriptions configured on replicas
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/publish/
      # @see https://valkey.io/commands/spublish/
      def publish(message, channel, sharded: false)
        @pubsub.publish(message, channel, sharded: sharded)
      end

      # Get the next Pub/Sub message, blocking until one is available.
      #
      # @example Consume messages until the client is closed
      #   while (message = valkey.get_pubsub_message)
      #     handle(message.channel, message.message)
      #   end
      #
      # @return [Valkey::Glide::PubSub::Message, nil] the message, or `nil` once the client is closed.
      #   `#pattern` is set only when the push was a `PMESSAGE`
      def get_pubsub_message
        @pubsub.get_message
      end

      # Get the next Pub/Sub message if one is already queued. Never blocks.
      #
      # @example Poll for a message
      #   valkey.try_get_pubsub_message
      #     # => #<struct Valkey::Glide::PubSub::Message message="hi", channel="channel1", pattern=nil>
      # @example Poll when nothing is queued
      #   valkey.try_get_pubsub_message
      #     # => nil
      #
      # @return [Valkey::Glide::PubSub::Message, nil] the message, or `nil` when the queue is empty or the
      #   client is closed. `#pattern` is set only when the push was a `PMESSAGE`
      def try_get_pubsub_message
        @pubsub.try_get_message
      end

      # Get this connection's subscription state: what the client asked for and what the server confirmed.
      #
      # @example Compare desired and actual subscriptions
      #   state = valkey.get_subscriptions
      #   state.desired_subscriptions
      #     # => {exact: ["channel1"], pattern: ["news.*"], sharded: ["shard1"]}
      #   state.actual_subscriptions
      #     # => {exact: ["channel1"], pattern: [], sharded: ["shard1"]}
      #
      # @return [Valkey::Glide::PubSub::SubscriptionState] both hashes are keyed `:exact`, `:pattern` and
      #   `:sharded`, mapping to `Array<String>`; standalone connections omit `:sharded`
      # @raise [NotImplementedError] this method is not implemented yet
      def get_subscriptions
        @pubsub.get_subscriptions
      end

      # List the currently active channels, that is, the channels with at least one subscriber.
      #
      # In cluster mode the command is routed to all nodes and the responses are combined.
      #
      # @example List all active channels
      #   valkey.pubsub_channels
      #     # => ["channel1", "channel2"]
      # @example List active channels matching a pattern
      #   valkey.pubsub_channels("news.*")
      #     # => ["news.sports", "news.weather"]
      #
      # @param [String, nil] pattern a glob-style pattern to match active channels against; if not provided,
      #   all active channels are returned
      # @return [Array<String>] the active channels matching the given pattern
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/pubsub-channels/
      def pubsub_channels(pattern = nil)
        @pubsub.pubsub_channels(pattern)
      end

      # Get the number of unique patterns that are subscribed to by clients.
      #
      # In cluster mode the command is routed to all nodes and the counts are summed.
      #
      # This is the total number of unique patterns all the clients are subscribed to, not the count of
      # clients subscribed to patterns.
      #
      # @example Get the pattern count
      #   valkey.pubsub_numpat
      #     # => 3
      #
      # @return [Integer] the number of unique patterns
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/pubsub-numpat/
      def pubsub_numpat
        @pubsub.pubsub_numpat
      end

      # Get the number of subscribers for the specified channels, exclusive of clients subscribed to patterns.
      #
      # In cluster mode the command is routed to all nodes and the counts are combined.
      #
      # @example Get subscriber counts
      #   valkey.pubsub_numsub("channel1", "channel2")
      #     # => {"channel1" => 5, "channel2" => 3}
      # @example Call it without channels
      #   valkey.pubsub_numsub
      #     # => {}
      #
      # @param [Array<String>] channels the channels to query for the number of subscribers; an empty list
      #   returns an empty hash
      # @return [Hash{String => Integer}] the channel names mapped to their number of subscribers
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/pubsub-numsub/
      def pubsub_numsub(*channels)
        @pubsub.pubsub_numsub(*channels)
      end

      # List the currently active sharded channels, that is, the ones with at least one subscriber.
      #
      # In cluster mode the command is routed to all nodes and the responses are combined.
      #
      # Only available in cluster mode (`cluster_mode: true`). Since: Valkey version 7.0.0.
      #
      # @example List all active shard channels
      #   valkey.pubsub_shardchannels
      #     # => ["shard1", "shard2"]
      # @example List active shard channels matching a pattern
      #   valkey.pubsub_shardchannels("shard.*")
      #     # => ["shard.1", "shard.2"]
      #
      # @param [String, nil] pattern a glob-style pattern to match active sharded channels against; if not
      #   provided, all active sharded channels are returned
      # @return [Array<String>] the active sharded channels matching the given pattern
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/pubsub-shardchannels/
      def pubsub_shardchannels(pattern = nil)
        @pubsub.pubsub_shardchannels(pattern)
      end

      # Get the number of subscribers for the specified sharded channels, exclusive of clients subscribed to
      # patterns.
      #
      # Only available in cluster mode (`cluster_mode: true`). Since: Valkey version 7.0.0.
      #
      # @example Get shard subscriber counts
      #   valkey.pubsub_shardnumsub("shard1", "shard2")
      #     # => {"shard1" => 2, "shard2" => 1}
      # @example Call it without channels
      #   valkey.pubsub_shardnumsub
      #     # => {}
      #
      # @param [Array<String>] channels the sharded channels to query for the number of subscribers; an empty
      #   list returns an empty hash
      # @return [Hash{String => Integer}] the sharded channel names mapped to their number of subscribers
      # @raise [NotImplementedError] this method is not implemented yet
      #
      # @see https://valkey.io/commands/pubsub-shardnumsub/
      def pubsub_shardnumsub(*channels)
        @pubsub.pubsub_shardnumsub(*channels)
      end
    end
  end
end
