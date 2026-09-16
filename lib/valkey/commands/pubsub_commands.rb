# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands for Valkey Pub/Sub.
    #
    # Pub/Sub requires the RESP3 protocol. Subscriptions can be declared when the client is created, and are
    # applied via SUBSCRIBE/PSUBSCRIBE/SSUBSCRIBE during connection establishment:
    #
    # @example
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
    # * Lazy: the `_lazy` subscribe and unsubscribe methods return without waiting for the server to confirm
    #   the change; read back {#get_subscriptions} to see the subscriptions the server actually has.
    #
    # @example PubSub with callback
    #   valkey = Valkey.new(
    #     protocol: :resp3,
    #     pubsub: {
    #       subscriptions: { exact: ["news"], pattern: ["news.*"] },
    #       callback: ->(message, context) { context[:messages] << [message.channel, message.message] },
    #       context: { messages: [] }
    #     }
    #   )
    #
    # @note While the callback executes it holds the GVL, blocking the Ruby runtime until it
    #   returns. A slow callback becomes a bottleneck for the whole application, so avoid
    #   costly operations in it.
    #
    # @note The callback may be invoked during initial connection, before Valkey.new returns.
    #   Do not reference the client being constructed from inside the callback, and
    #   any state the callback needs at delivery time should be passed via the context
    #   instead
    #
    # @see https://valkey.io/docs/topics/pubsub/
    # @see https://valkey.io/commands/#pubsub
    #
    module PubSubCommands
      # Subscription mode mapped to the integer key glide-core expects
      SUBSCRIPTION_MODES = { exact: 0, pattern: 1, sharded: 2 }.freeze

      # PubSub requires RESP3
      RESP3_VALUES = [:resp3, "resp3", 3].freeze

      HashifyNumsub = lambda { |reply|
        Utils::Hashify.call(reply).to_h { |channel, count| [channel.to_s, count.to_i] }
      }
      private_constant :HashifyNumsub

      SymbolizeSubscriptionModes = lambda { |payload|
        Utils::Hashify.call(payload).to_h do |mode, channels|
          [mode.to_s.downcase.to_sym, Array(channels).map(&:to_s).uniq]
        end
      }
      private_constant :SymbolizeSubscriptionModes

      StateifySubscriptions = lambda { |reply|
        unless reply.is_a?(Array) && reply.size == 4
          raise CommandError,
                "Unexpected GET_SUBSCRIPTIONS response: expected a 4-element array, got: #{reply.inspect}"
        end

        Glide::PubSubState.new(
          SymbolizeSubscriptionModes.call(reply[1]),
          SymbolizeSubscriptionModes.call(reply[3])
        )
      }
      private_constant :StateifySubscriptions

      # Subscribe to exact channels, waiting for the server to confirm the subscription.
      #
      # @example Subscribe to channels
      #   valkey.subscribe("channel1", "channel2")
      #
      # @param [Array<String>] channels the channels to subscribe to; an empty list is rejected
      # @param [Integer, Float] timeout_ms maximum time in milliseconds to wait for the server to
      #   confirm; `0` blocks indefinitely
      # @return [void] returns once the server has confirmed the subscription
      # @raise [ArgumentError] on argument errors
      # @raise [Valkey::Resp3RequiredError] GLIDE Pub/Sub requires RESP3
      # @raise [Valkey::TimeoutError] if the timeout expires before the server confirms
      #
      # @see https://valkey.io/commands/subscribe/
      def subscribe(*channels, timeout_ms: 0)
        validate_resp3!
        # glide-core already rejects an empty list with this message, but as
        # ErrorKind::ClientError, which surfaces here as the too-generic
        # Valkey::CommandError.
        # TODO: push this upstream once glide-core reports it as an argument
        # error, then drop the check here.
        raise ArgumentError, "No channels provided for subscription" if channels.empty?

        send_command(RequestType::SUBSCRIBE_BLOCKING, channels.map(&:to_s) + [parse_timeout(timeout_ms)])
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
      # @param [Integer, Float] timeout_ms maximum time in milliseconds to wait for the server to
      #   confirm; `0` blocks indefinitely
      # @return [void] returns once the server has confirmed the change
      # @raise [ArgumentError] on argument errors
      # @raise [Valkey::Resp3RequiredError] GLIDE Pub/Sub requires RESP3
      # @raise [Valkey::TimeoutError] if the timeout expires before the server confirms
      #
      # @see https://valkey.io/commands/unsubscribe/
      def unsubscribe(*channels, timeout_ms: 0)
        validate_resp3!

        send_command(RequestType::UNSUBSCRIBE_BLOCKING, channels.map(&:to_s) + [parse_timeout(timeout_ms)])
      end

      # Subscribe to channel patterns, waiting for the server to confirm the subscription.
      #
      # @example Subscribe to patterns
      #   valkey.psubscribe("news.*", "events.*")
      #
      # @param [Array<String>] patterns the glob-style patterns to subscribe to; an empty list is rejected
      # @param [Integer, Float] timeout_ms maximum time in milliseconds to wait for the server to
      #   confirm; `0` blocks indefinitely
      # @return [void] returns once the server has confirmed the subscription
      # @raise [ArgumentError] if timeout_ms is negative
      # @raise [Valkey::Resp3RequiredError] GLIDE Pub/Sub requires RESP3
      # @raise [Valkey::TimeoutError] if the timeout expires before the server confirms
      #
      # @see https://valkey.io/commands/psubscribe/
      def psubscribe(*patterns, timeout_ms: 0)
        validate_resp3!
        raise ArgumentError, "No patterns provided for subscription" if patterns.empty?

        send_command(RequestType::PSUBSCRIBE_BLOCKING, patterns.map(&:to_s) + [parse_timeout(timeout_ms)])
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
      # @param [Integer, Float] timeout_ms maximum time in milliseconds to wait for the server to
      #   confirm; `0` blocks indefinitely
      # @return [void] returns once the server has confirmed the change
      # @raise [ArgumentError] if timeout_ms is negative
      # @raise [Valkey::Resp3RequiredError] GLIDE Pub/Sub requires RESP3
      # @raise [Valkey::TimeoutError] if the timeout expires before the server confirms
      #
      # @see https://valkey.io/commands/punsubscribe/
      def punsubscribe(*patterns, timeout_ms: 0)
        validate_resp3!

        send_command(RequestType::PUNSUBSCRIBE_BLOCKING, patterns.map(&:to_s) + [parse_timeout(timeout_ms)])
      end

      # Subscribe to sharded channels, waiting for the server to confirm the subscription.
      #
      # Only available in cluster mode (`cluster_mode: true`). Since: Valkey version 7.0.0.
      #
      # @example Subscribe to shard channels
      #   valkey.ssubscribe("shard1", "shard2")
      #
      # @param [Array<String>] channels the sharded channels to subscribe to; an empty list is rejected
      # @param [Integer, Float] timeout_ms maximum time in milliseconds to wait for the server to
      #   confirm; `0` blocks indefinitely
      # @return [void] returns once the server has confirmed the subscription
      # @raise [ArgumentError] if the client is not in cluster mode, or if timeout_ms is negative
      # @raise [Valkey::Resp3RequiredError] GLIDE Pub/Sub requires RESP3
      # @raise [Valkey::TimeoutError] if the timeout expires before the server confirms
      #
      # @see https://valkey.io/commands/ssubscribe/
      def ssubscribe(*channels, timeout_ms: 0)
        validate_resp3!
        validate_cluster_mode!(__method__)
        raise ArgumentError, "No channels provided for subscription" if channels.empty?

        send_command(RequestType::SSUBSCRIBE_BLOCKING, channels.map(&:to_s) + [parse_timeout(timeout_ms)])
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
      # @param [Integer, Float] timeout_ms maximum time in milliseconds to wait for the server to
      #   confirm; `0` blocks indefinitely
      # @return [void] returns once the server has confirmed the change
      # @raise [ArgumentError] if the client is not in cluster mode, or if timeout_ms is negative
      # @raise [Valkey::Resp3RequiredError] GLIDE Pub/Sub requires RESP3
      # @raise [Valkey::TimeoutError] if the timeout expires before the server confirms
      #
      # @see https://valkey.io/commands/sunsubscribe/
      def sunsubscribe(*channels, timeout_ms: 0)
        validate_resp3!
        validate_cluster_mode!(__method__)

        send_command(RequestType::SUNSUBSCRIBE_BLOCKING, channels.map(&:to_s) + [parse_timeout(timeout_ms)])
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
      # @raise [ArgumentError] on argument errors
      # @raise [Valkey::Resp3RequiredError] GLIDE Pub/Sub requires RESP3
      #
      # @see https://valkey.io/commands/subscribe/
      def subscribe_lazy(*channels)
        send_lazy_subscription(RequestType::SUBSCRIBE, channels, reject_empty: true)
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
      # @raise [Valkey::Resp3RequiredError] GLIDE Pub/Sub requires RESP3
      #
      # @see https://valkey.io/commands/unsubscribe/
      def unsubscribe_lazy(*channels)
        send_lazy_subscription(RequestType::UNSUBSCRIBE, channels)
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
      # @raise [ArgumentError] on argument errors
      # @raise [Valkey::Resp3RequiredError] GLIDE Pub/Sub requires RESP3
      #
      # @see https://valkey.io/commands/psubscribe/
      def psubscribe_lazy(*patterns)
        send_lazy_subscription(RequestType::PSUBSCRIBE, patterns, reject_empty: true, noun: "patterns")
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
      # @raise [Valkey::Resp3RequiredError] GLIDE Pub/Sub requires RESP3
      #
      # @see https://valkey.io/commands/punsubscribe/
      def punsubscribe_lazy(*patterns)
        send_lazy_subscription(RequestType::PUNSUBSCRIBE, patterns)
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
      # @raise [ArgumentError] if the client is not in cluster mode, or if the channel list is empty
      # @raise [Valkey::Resp3RequiredError] GLIDE Pub/Sub requires RESP3
      #
      # @see https://valkey.io/commands/ssubscribe/
      def ssubscribe_lazy(*channels)
        validate_cluster_mode!(__method__)
        send_lazy_subscription(RequestType::SSUBSCRIBE, channels, reject_empty: true)
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
      # @raise [ArgumentError] if the client is not in cluster mode
      # @raise [Valkey::Resp3RequiredError] GLIDE Pub/Sub requires RESP3
      #
      # @see https://valkey.io/commands/sunsubscribe/
      def sunsubscribe_lazy(*channels)
        validate_cluster_mode!(__method__)
        send_lazy_subscription(RequestType::SUNSUBSCRIBE, channels)
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
      #
      # @see https://valkey.io/commands/publish/
      # @see https://valkey.io/commands/spublish/
      def publish(message, channel, sharded: false)
        request_type = sharded ? RequestType::SPUBLISH : RequestType::PUBLISH
        send_command(request_type, [channel.to_s, message.to_s])
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
      # @return [Valkey::Glide::PubSubState] both hashes are keyed `:exact`, `:pattern`
      #   and `:sharded`, mapping to `Array<String>`; standalone connections omit `:sharded`
      def get_subscriptions
        send_command(RequestType::GET_SUBSCRIPTIONS, &StateifySubscriptions)
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
      #
      # @see https://valkey.io/commands/pubsub-channels/
      def pubsub_channels(pattern = nil)
        send_command(RequestType::PUBSUB_CHANNELS, [pattern].compact.map(&:to_s))
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
      #
      # @see https://valkey.io/commands/pubsub-numpat/
      def pubsub_numpat
        send_command(RequestType::PUBSUB_NUM_PAT)
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
      #
      # @see https://valkey.io/commands/pubsub-numsub/
      def pubsub_numsub(*channels)
        send_command(RequestType::PUBSUB_NUM_SUB, channels.map(&:to_s), &HashifyNumsub)
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
      #
      # @see https://valkey.io/commands/pubsub-shardchannels/
      def pubsub_shardchannels(pattern = nil)
        send_command(RequestType::PUBSUB_SHARD_CHANNELS, [pattern].compact.map(&:to_s))
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
      #
      # @see https://valkey.io/commands/pubsub-shardnumsub/
      def pubsub_shardnumsub(*channels)
        send_command(RequestType::PUBSUB_SHARD_NUM_SUB, channels.map(&:to_s), &HashifyNumsub)
      end

      # Dispatch a PUBSUB introspection subcommand. Mirrors redis-rb's `pubsub(subcommand, *args)`.
      #
      # The subcommand is matched case-insensitively and may be a Symbol or a String. Supported
      # subcommands are `channels`, `numpat`, `numsub`, `shardchannels` and `shardnumsub`; each
      # dispatches to the corresponding `pubsub_*` method and returns its converted result.
      #
      # @example List active channels matching a pattern
      #   valkey.pubsub(:channels, "news.*")
      #     # => ["news.sports", "news.weather"]
      # @example Get the pattern count
      #   valkey.pubsub(:numpat)
      #     # => 3
      # @example Get subscriber counts
      #   valkey.pubsub(:numsub, "channel1", "channel2")
      #     # => {"channel1" => 5, "channel2" => 3}
      #
      # @param [Symbol, String] subcommand the PUBSUB subcommand to run
      # @param [Array<String>] args the arguments forwarded to the subcommand
      # @return [Array<String>, Integer, Hash{String => Integer}] the subcommand's result
      # @raise [ArgumentError] if the subcommand is not a known PUBSUB subcommand
      #
      # @see https://valkey.io/commands/#pubsub
      def pubsub(subcommand, *args)
        case subcommand.to_s.downcase
        when "channels"      then pubsub_channels(*args)
        when "numpat"        then pubsub_numpat
        when "numsub"        then pubsub_numsub(*args)
        when "shardchannels" then pubsub_shardchannels(*args)
        when "shardnumsub"   then pubsub_shardnumsub(*args)
        else
          raise ArgumentError, "Unknown PUBSUB subcommand: #{subcommand.inspect}"
        end
      end

      # Get the next Pub/Sub message, blocking until one is available.
      #
      # @example Consume messages until the client is closed
      #   while (message = valkey.get_pubsub_message)
      #     handle(message.channel, message.message)
      #   end
      #
      # @return [Valkey::Glide::PubSubMessage, nil] the message, or `nil` once the client is closed.
      #   `#pattern` is set only when the push was a `PMESSAGE`
      # @raise [Valkey::Resp3RequiredError] GLIDE Pub/Sub requires RESP3
      # @raise [Valkey::InvalidClientOptionError] on client-side configuration errors
      def get_pubsub_message
        validate_resp3!
        @pubsub_receiver.pop
      end

      # Get the next Pub/Sub message if one is already queued. Never blocks.
      #
      # @example Poll for a message
      #   valkey.try_get_pubsub_message
      #     # => #<struct Valkey::Glide::PubSubMessage message="hi", channel="channel1", pattern=nil>
      # @example Poll when nothing is queued
      #   valkey.try_get_pubsub_message
      #     # => nil
      #
      # @return [Valkey::Glide::PubSubMessage, nil] the message, or `nil` when the queue is empty or the
      #   client is closed. `#pattern` is set only when the push was a `PMESSAGE`
      # @raise [Valkey::Resp3RequiredError] GLIDE Pub/Sub requires RESP3
      # @raise [Valkey::InvalidClientOptionError] on client-side configuration errors
      def try_get_pubsub_message
        validate_resp3!
        @pubsub_receiver.try_pop
      end

      private

      def validate_resp3!
        raise Resp3RequiredError, protocol unless RESP3_VALUES.include?(protocol)
      end

      def validate_cluster_mode!(command)
        return if cluster_mode?

        raise ArgumentError, "#{command} is only available in cluster mode."
      end

      def send_lazy_subscription(request_type, channels, reject_empty: false, noun: "channels")
        validate_resp3!
        raise ArgumentError, "No #{noun} provided for subscription" if reject_empty && channels.empty?

        send_command(request_type, channels.map(&:to_s))
      end

      # glide-core takes the timeout as the last command argument, in whole
      # milliseconds, and reads a zero as "no deadline".
      def parse_timeout(timeout_ms)
        valid = timeout_ms.is_a?(Numeric) && !timeout_ms.negative?
        raise ArgumentError, "Timeout must be a non-negative number, got: #{timeout_ms.inspect}" unless valid
        return "0" if timeout_ms.zero?

        # Handling floats.
        [timeout_ms.to_i, 1].max.to_s
      end
    end
  end
end
