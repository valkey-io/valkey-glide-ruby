# frozen_string_literal: true

class Valkey
  # GLIDE-specific internals. Nothing here is public API.
  module Glide
    # The wrapper around a Valkey client to handle all its PubSub functionalities.
    #
    # Pub/Sub requires the RESP3 protocol, which `parse_config` enforces on the
    # connect-time `pubsub:` option:
    #
    #   pubsub: {
    #     subscriptions: {
    #       exact: ["news"],           # channel names
    #       pattern: ["news.*"],       # channel name patterns
    #       sharded: ["shard-chan"]    # sharded channels, cluster mode only
    #     }
    #   }
    #
    # There are three ways to receive messages:
    #
    # * Inline: messages are queued and read with {#get_message} or
    #   {#try_get_message}.
    # * Callback: a `callback:` proc receives every message instead, along with
    #   an arbitrary `context:`. Not supported yet.
    # * Lazy: the `_lazy` subscribe and unsubscribe methods return without
    #   waiting for the server to confirm the change; read back
    #   {#get_subscriptions} for the subscriptions the server actually has.
    #
    # Blocking methods take `timeout:` in seconds. glide-core receives it as an
    # integer millisecond count appended as the last command argument, where `0`
    # means "block indefinitely", so `nil` is sent as `0`.
    #
    # Only `parse_config`, the message queue and {#close} are implemented; the
    # rest of the surface raises NotImplementedError.
    #
    # @see https://valkey.io/docs/topics/pubsub/
    # @api private
    class PubSub
      # Push kinds as delivered by the FFI handler's `kind` argument.
      # Mirrors `PushKind` in valkey-glide/ffi/src/lib.rs; keep in sync there.
      module PushKind
        DISCONNECTION = 0
        OTHER = 1
        INVALIDATE = 2
        MESSAGE = 3
        PMESSAGE = 4
        SMESSAGE = 5
        UNSUBSCRIBE = 6
        PUNSUBSCRIBE = 7
        SUNSUBSCRIBE = 8
        SUBSCRIBE = 9
        PSUBSCRIBE = 10
        SSUBSCRIBE = 11

        # The only kinds that carry a payload for the user.
        MESSAGE_KINDS = [MESSAGE, PMESSAGE, SMESSAGE].freeze
      end

      # One delivered push: the incoming `message`, the `channel` that carried
      # it, and the `pattern` that matched it. `pattern` is set only for
      # PMESSAGE; exact and sharded pushes leave it nil.
      Message = Struct.new(:message, :channel, :pattern)

      # A connection's subscriptions, as returned by {#get_subscriptions}. Both
      # fields are a `Hash` keyed by `:exact`, `:pattern` and `:sharded`, each
      # mapping to an `Array<String>`. `desired_subscriptions` is what the
      # client asked for, `actual_subscriptions` is what the server currently
      # has. Standalone connections omit `:sharded` entirely.
      SubscriptionState = Struct.new(:desired_subscriptions, :actual_subscriptions)

      # Subscription mode to the integer key glide-core expects in the
      # connection JSON: `:exact` uses exact channel names, `:pattern` uses
      # glob-style channel name patterns, `:sharded` uses sharded Pub/Sub and is
      # cluster-only.
      SUBSCRIPTION_MODES = { exact: 0, pattern: 1, sharded: 2 }.freeze

      # PubSub requires RESP3
      RESP3_VALUES = [:resp3, "resp3", 3].freeze

      class << self
        # Parses and validates the `pubsub:` option.
        #
        # @example pubsub_configs:
        #   {
        #     subscriptions: {
        #       exact:   ["news", "alerts"],  # exact matches
        #       pattern: ["news.*"],          # glob patterns
        #       sharded: ["shard-chan"]       # cluster mode
        #     },
        #     callback: ->(message, context) { ... },  # callback handler
        #     context: my_app_state                   # callback context
        #   }
        #
        # @param pubsub_configs [Hash, nil] the `pubsub:` options: the channels
        #   and patterns to subscribe to at connection time under
        #   `:subscriptions`, keyed by mode, an optional `:callback` to accept
        #   the incoming messages and an arbitrary `:context` passed to it.
        # @param protocol [Symbol, String, Integer, nil] the `protocol:` option.
        #   Subscriptions require RESP3.
        # @return [Hash] the subscriptions keyed by the integer mode glide-core
        #   expects, or an empty Hash when nothing is subscribed to.
        # @raise [ArgumentError] on an unknown subscription mode, or on
        #   subscriptions configured with a protocol other than RESP3.
        # @see https://valkey.io/docs/topics/pubsub/
        def parse_config(pubsub_configs, protocol: nil)
          pubsub_configs ||= {}
          subscriptions = pubsub_configs[:subscriptions] || {}

          validate!(subscriptions, protocol: protocol)

          to_ffi(pubsub_configs)
        end

        private

        # Converts the configuration to what the ffi expects.
        def to_ffi(pubsub_configs)
          subscriptions = pubsub_configs[:subscriptions] || {}
          return {} if subscriptions.empty?

          mapped = subscriptions
                   .transform_keys { |mode| SUBSCRIPTION_MODES.fetch(mode).to_s }
                   .transform_values { |channels| Array(channels).map(&:to_s) }

          { "pubsub_subscriptions" => mapped }
        end

        def validate!(subscriptions, protocol:)
          return if subscriptions.empty?

          unknown_modes = subscriptions.keys - SUBSCRIPTION_MODES.keys
          raise ArgumentError, unknown_mode_message(unknown_modes) if unknown_modes.any?

          return if RESP3_VALUES.include?(protocol)

          raise ArgumentError, "Pub/Sub requires the RESP3 protocol. Found #{protocol.inspect}"
        end

        def unknown_mode_message(unknown_modes)
          "Unknown Pub/Sub subscription mode(s): #{unknown_modes.join(', ')}. " \
            "Valid modes are: #{SUBSCRIPTION_MODES.keys.join(', ')}"
        end
      end

      # @param client [Valkey] A valkey client connection.
      # @param cluster_mode [Boolean] The client cluster mode.
      def initialize(client, cluster_mode:)
        @client = client
        @cluster_mode = cluster_mode
        @message_queue = Thread::Queue.new

        # The handler proc for receiving messages from the FFI.
        @ffi_handler = build_ffi_handler
      end

      attr_reader :ffi_handler

      # Gets a Pub/Sub message, blocking until one is available.
      #
      # @return [Message, nil] the next message, or nil once the message queue
      #   is closed.
      def get_message
        @message_queue.pop
      end

      # Gets a Pub/Sub message without blocking.
      #
      # @return [Message, nil] the next message, or nil when the message queue
      #   is empty or closed.
      def try_get_message
        @message_queue.pop(true)
      rescue ThreadError
        nil
      end

      # Releases the Pub/Sub resources, closing the message queue. Callers
      # blocked in {#get_message} are woken with nil.
      def close
        @message_queue.close
      end

      # Subscribes to exact channels (blocking). Updates the client's desired
      # subscription state and waits for the server's confirmation.
      #
      # @param channels [Array<String>] the channel names to subscribe to. An
      #   empty list is rejected with "No channels provided for subscription".
      # @param timeout [Float, Integer, nil] maximum time in seconds to wait for
      #   the server's confirmation. `nil` blocks indefinitely.
      # @return [void] once the server has confirmed the subscription.
      # @raise [ArgumentError] on a negative timeout.
      # @raise [Valkey::TimeoutError] when the timeout expires before the
      #   server confirms.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/subscribe/
      def subscribe(*channels, timeout: nil) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Unsubscribes from exact channels (blocking). Updates the client's
      # desired subscription state and waits for the server's confirmation.
      #
      # @param channels [Array<String>] the channel names to unsubscribe from.
      #   Empty unsubscribes from every exact channel.
      # @param timeout [Float, Integer, nil] maximum time in seconds to wait for
      #   the server's confirmation. `nil` blocks indefinitely.
      # @return [void] once the server has confirmed the unsubscription.
      # @raise [ArgumentError] on a negative timeout.
      # @raise [Valkey::TimeoutError] when the timeout expires before the
      #   server confirms.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/unsubscribe/
      def unsubscribe(*channels, timeout: nil) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Subscribes to channel patterns (blocking). Updates the client's desired
      # subscription state and waits for the server's confirmation.
      #
      # @param patterns [Array<String>] the glob-style patterns to subscribe to,
      #   for example `"news.*"`. An empty list is rejected with "No channels
      #   provided for subscription".
      # @param timeout [Float, Integer, nil] maximum time in seconds to wait for
      #   the server's confirmation. `nil` blocks indefinitely.
      # @return [void] once the server has confirmed the subscription.
      # @raise [ArgumentError] on a negative timeout.
      # @raise [Valkey::TimeoutError] when the timeout expires before the
      #   server confirms.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/psubscribe/
      def psubscribe(*patterns, timeout: nil) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Unsubscribes from channel patterns (blocking). Updates the client's
      # desired subscription state and waits for the server's confirmation.
      #
      # @param patterns [Array<String>] the patterns to unsubscribe from. Empty
      #   unsubscribes from every pattern.
      # @param timeout [Float, Integer, nil] maximum time in seconds to wait for
      #   the server's confirmation. `nil` blocks indefinitely.
      # @return [void] once the server has confirmed the unsubscription.
      # @raise [ArgumentError] on a negative timeout.
      # @raise [Valkey::TimeoutError] when the timeout expires before the
      #   server confirms.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/punsubscribe/
      def punsubscribe(*patterns, timeout: nil) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Subscribes to sharded channels (blocking). Updates the client's desired
      # subscription state and waits for the server's confirmation. Requires
      # `cluster_mode: true`; sharded Pub/Sub has no standalone equivalent.
      #
      # Since: Valkey version 7.0.0.
      #
      # @param channels [Array<String>] the sharded channel names to subscribe
      #   to. An empty list is rejected with "No channels provided for
      #   subscription".
      # @param timeout [Float, Integer, nil] maximum time in seconds to wait for
      #   the server's confirmation. `nil` blocks indefinitely.
      # @return [void] once the server has confirmed the subscription.
      # @raise [ArgumentError] on a negative timeout.
      # @raise [Valkey::TimeoutError] when the timeout expires before the
      #   server confirms.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/ssubscribe/
      def ssubscribe(*channels, timeout: nil) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Unsubscribes from sharded channels (blocking). Updates the client's
      # desired subscription state and waits for the server's confirmation.
      # Requires `cluster_mode: true`; sharded Pub/Sub has no standalone
      # equivalent.
      #
      # Since: Valkey version 7.0.0.
      #
      # @param channels [Array<String>] the sharded channel names to unsubscribe
      #   from. Empty unsubscribes from every sharded channel.
      # @param timeout [Float, Integer, nil] maximum time in seconds to wait for
      #   the server's confirmation. `nil` blocks indefinitely.
      # @return [void] once the server has confirmed the unsubscription.
      # @raise [ArgumentError] on a negative timeout.
      # @raise [Valkey::TimeoutError] when the timeout expires before the
      #   server confirms.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/sunsubscribe/
      def sunsubscribe(*channels, timeout: nil) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Subscribes to exact channels (non-blocking). Updates the client's
      # desired subscription state without waiting for the server's
      # confirmation, and returns as soon as the local state is updated. The
      # client subscribes asynchronously in the background. Use
      # {#get_subscriptions} to verify the actual server-side subscription
      # state.
      #
      # @param channels [Array<String>] the channel names to subscribe to. An
      #   empty list is rejected with "No channels provided for subscription".
      # @return [void] immediately, before the server confirms.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/subscribe/
      def subscribe_lazy(*channels) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Unsubscribes from exact channels (non-blocking). Updates the client's
      # desired subscription state without waiting for the server's
      # confirmation, and returns as soon as the local state is updated. Use
      # {#get_subscriptions} to verify the actual server-side subscription
      # state.
      #
      # @param channels [Array<String>] the channel names to unsubscribe from.
      #   Empty unsubscribes from every exact channel.
      # @return [void] immediately, before the server confirms.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/unsubscribe/
      def unsubscribe_lazy(*channels) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Subscribes to channel patterns (non-blocking). Updates the client's
      # desired subscription state without waiting for the server's
      # confirmation, and returns as soon as the local state is updated. The
      # client subscribes asynchronously in the background. Use
      # {#get_subscriptions} to verify the actual server-side subscription
      # state.
      #
      # @param patterns [Array<String>] the glob-style patterns to subscribe to,
      #   for example `"news.*"`. An empty list is rejected with "No channels
      #   provided for subscription".
      # @return [void] immediately, before the server confirms.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/psubscribe/
      def psubscribe_lazy(*patterns) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Unsubscribes from channel patterns (non-blocking). Updates the client's
      # desired subscription state without waiting for the server's
      # confirmation, and returns as soon as the local state is updated. Use
      # {#get_subscriptions} to verify the actual server-side subscription
      # state.
      #
      # @param patterns [Array<String>] the patterns to unsubscribe from. Empty
      #   unsubscribes from every pattern.
      # @return [void] immediately, before the server confirms.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/punsubscribe/
      def punsubscribe_lazy(*patterns) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Subscribes to sharded channels (non-blocking). Updates the client's
      # desired subscription state without waiting for the server's
      # confirmation, and returns as soon as the local state is updated. The
      # client subscribes asynchronously in the background. Use
      # {#get_subscriptions} to verify the actual server-side subscription
      # state. Requires `cluster_mode: true`; sharded Pub/Sub has no standalone
      # equivalent.
      #
      # Since: Valkey version 7.0.0.
      #
      # @param channels [Array<String>] the sharded channel names to subscribe
      #   to. An empty list is rejected with "No channels provided for
      #   subscription".
      # @return [void] immediately, before the server confirms.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/ssubscribe/
      def ssubscribe_lazy(*channels) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Unsubscribes from sharded channels (non-blocking). Updates the client's
      # desired subscription state without waiting for the server's
      # confirmation, and returns as soon as the local state is updated. Use
      # {#get_subscriptions} to verify the actual server-side subscription
      # state. Requires `cluster_mode: true`; sharded Pub/Sub has no standalone
      # equivalent.
      #
      # Since: Valkey version 7.0.0.
      #
      # @param channels [Array<String>] the sharded channel names to unsubscribe
      #   from. Empty unsubscribes from every sharded channel.
      # @return [void] immediately, before the server confirms.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/sunsubscribe/
      def sunsubscribe_lazy(*channels) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Publishes a message on a Pub/Sub channel. Aggregates the PUBLISH and
      # SPUBLISH functionalities, the mode selected by `sharded`. In both modes
      # the request is routed using the hashed channel as key. The message comes
      # first, matching the other GLIDE clients.
      #
      # @param message [String] the message to publish.
      # @param channel [String] the channel to publish the message on.
      # @param sharded [Boolean] use sharded Pub/Sub mode. Available since
      #   Valkey version 7.0, and requires `cluster_mode: true`.
      # @return [Integer] the number of subscriptions that received the message.
      #   In cluster mode that is the count on the node the request was routed
      #   to; in standalone it is the count on the primary node, which does not
      #   include subscriptions configured on replicas.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/publish/
      # @see https://valkey.io/commands/spublish/
      def publish(message, channel, sharded: false) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # The connection's subscription state: what the client asked for, and what
      # the server currently has. The way to confirm the outcome of a lazy
      # subscribe or unsubscribe call.
      #
      # @return [SubscriptionState] the desired and actual subscriptions.
      # @raise [NotImplementedError] this method is not implemented yet.
      def get_subscriptions = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Lists the currently active channels, that is the channels with at least
      # one exact subscriber. The command is routed to all nodes and the
      # responses are aggregated into a single array.
      #
      # @param pattern [String, nil] a glob-style pattern to match active
      #   channels against. `nil` returns all active channels.
      # @return [Array<String>] the active channels matching the given pattern.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/pubsub-channels/
      def pubsub_channels(pattern = nil) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Counts the unique patterns clients are subscribed to. That is the total
      # number of unique patterns across all clients, not the number of clients
      # subscribed to patterns. The command is routed to all nodes and the
      # responses are aggregated into their sum.
      #
      # @return [Integer] the number of unique patterns.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/pubsub-numpat/
      def pubsub_numpat = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Counts the subscribers of the given channels, exclusive of clients
      # subscribed to patterns. The command is routed to all nodes and the
      # responses are aggregated into a single Hash.
      #
      # @param channels [Array<String>] the channels to query for the number of
      #   subscribers. Calling this without channels is valid and returns an
      #   empty Hash.
      # @return [Hash{String => Integer}] the channel names mapped to their
      #   number of subscribers.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/pubsub-numsub/
      def pubsub_numsub(*channels) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Lists the currently active sharded channels, that is the sharded
      # channels with at least one subscriber. The command is routed to all nodes
      # and the responses are aggregated into a single array.
      #
      # Since: Valkey version 7.0.0.
      #
      # @param pattern [String, nil] a glob-style pattern to match active sharded
      #   channels against. `nil` returns all active sharded channels.
      # @return [Array<String>] the active sharded channels matching the given
      #   pattern.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/pubsub-shardchannels/
      def pubsub_shardchannels(pattern = nil) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Counts the subscribers of the given sharded channels, exclusive of
      # clients subscribed to patterns. The command is routed to all nodes and
      # the responses are aggregated into a single Hash.
      #
      # Since: Valkey version 7.0.0.
      #
      # @param channels [Array<String>] the sharded channels to query for the
      #   number of subscribers. Calling this without channels is valid and
      #   returns an empty Hash.
      # @return [Hash{String => Integer}] the sharded channel names mapped to
      #   their number of subscribers.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/pubsub-shardnumsub/
      def pubsub_shardnumsub(*channels) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      # Raw PUBSUB passthrough, dispatching to the matching `pubsub_*` method.
      #
      # @param subcommand [String, Symbol] one of `channels`, `numpat`,
      #   `numsub`, `shardchannels` or `shardnumsub`.
      # @param args [Array] the arguments of the subcommand.
      # @return [Array<String>, Integer, Hash{String => Integer}] whatever the
      #   target method returns.
      # @raise [NotImplementedError] this method is not implemented yet.
      # @see https://valkey.io/commands/#pubsub
      def pubsub(subcommand, *args) = raise(NotImplementedError, "#{__method__} is not implemented yet")

      private

      # Builds the proc handed to the FFI.
      #
      # Runs on a Rust thread the Ruby runtime did not create, on a single push
      # worker, with the GVL borrowed. Keep it thin: copy out, enqueue, return.
      # No user code, no FFI re-entry, no blocking I/O -- anything slow here
      # stalls every message behind it. The pointers are freed when it returns,
      # so the copy has to happen synchronously.
      #
      # TODO: unfinished -- the handler still has to:
      #   - return early unless PushKind::MESSAGE_KINDS covers kind
      #   - log DISCONNECTION, drop the confirmation kinds silently
      #   - read_string(len) for message and channel; pattern is nil when
      #     pat_ptr is null (exact and sharded pushes)
      #   - deliver(Message.new(...))
      #   - rescue StandardError and swallow: an exception must never cross the
      #     FFI boundary
      def build_ffi_handler
        lambda do |_client_ptr, _kind, _msg_ptr, _msg_len, _chan_ptr, _chan_len, _pat_ptr, _pat_len|
        end
      end

      # Single delivery point, so push mode is added by branching here and
      # nothing else changes.
      #
      # TODO: unfinished -- callback branch:
      #   @callback.arity == 1 ? call(msg) : call(msg, @context).
      def deliver(message)
        @message_queue.push(message)
      end
    end
  end
end
