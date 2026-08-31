# frozen_string_literal: true

class Valkey
  # GLIDE-specific internals. Nothing here is public API.
  module Glide
    # The wrapper around a Valkey client to handle all its PubSub functionalities.
    #
    # TODO: https://github.com/valkey-io/valkey-glide-ruby/issues/135.
    #
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

      # One delivered push. `pattern` is set only for PMESSAGE.
      Message = Struct.new(:message, :channel, :pattern)

      # Subscription mode to the integer key glide-core expects in the
      # connection JSON.
      MODE_CODES = { exact: 0, pattern: 1, sharded: 2 }.freeze

      RESP2_OPTIONS = [:resp2, "resp2", 2].freeze

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
        # @param pubsub_configs [Hash, nil] the `pubsub:` options.
        # @param protocol [Symbol, String, Integer, nil] the `protocol:` option
        # @return [Hash] the input sanitized.
        # @raise [ArgumentError] on invalid arguments.
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
                   .transform_keys { |mode| MODE_CODES.fetch(mode).to_s }
                   .transform_values { |channels| Array(channels).map(&:to_s) }

          { "pubsub_subscriptions" => mapped }
        end

        def validate!(subscriptions, protocol:)
          return if subscriptions.empty?

          unknown_modes = subscriptions.keys - MODE_CODES.keys
          raise ArgumentError, unknown_mode_message(unknown_modes) if unknown_modes.any?

          raise ArgumentError, "Pub/Sub requires RESP3 protocol. Found #{protocol}" if RESP2_OPTIONS.include?(protocol)
        end

        def unknown_mode_message(unknown_modes)
          "Unknown Pub/Sub subscription mode(s): #{unknown_modes.join(', ')}. " \
            "Valid modes are: #{MODE_CODES.keys.join(', ')}"
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

      # Get the next message. Blocks until one is available.
      #
      # @return [Message, nil] nil once message queue is closed.
      def get_message
        @message_queue.pop
      end

      # Get the next message.
      #
      # @return [Message, nil] nil when message queue is empty or closed
      def try_get_message
        @message_queue.pop(true)
      rescue ThreadError
        nil
      end

      # Cleanup PubSub resources
      def close
        @message_queue.close
      end

      private

      # Builds the proc handed to the FFI.
      #
      # Runs on a Rust thread the Ruby runtime did not create, on a single push
      # worker, with the GVL borrowed. Keep it thin: copy out, enqueue, return.
      # No user code, no FFI re-entry, no blocking I/O -- anything slow here
      # stalls every message behind it. The pointers are freed when it returns,
      # so the copy has to happen synchronously.
      #
      #
      # TODO: https://github.com/valkey-io/valkey-glide-ruby/issues/135:
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
      # TODO: Unfinished -- callback branch:
      #   @callback.arity == 1 ? call(msg) : call(msg, @context). To be
      #   completed as part of
      #   https://github.com/valkey-io/valkey-glide-ruby/issues/135.
      def deliver(message)
        @message_queue.push(message)
      end
    end
  end
end
