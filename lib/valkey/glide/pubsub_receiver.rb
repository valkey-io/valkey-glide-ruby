# frozen_string_literal: true

class Valkey
  module Glide
    # Manages Pub/Sub messages from the core.
    #
    # @api private
    class PubSubReceiver
      # Push kinds as delivered by the FFI PubSub handler's `kind` argument.
      # Mirrors `PushKind` in valkey-glide/ffi/src/lib.rs; keep in sync there.
      #
      # @api private
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

      def self.make(pubsub_configs: {})
        configs = pubsub_configs || {}
        callback = configs[:callback]
        context = configs[:context]

        unless callback.nil?
          unless callback.respond_to?(:call)
            raise InvalidClientOptionError,
                  "Pub/Sub: callback must respond to #call, got: #{callback.class}"
          end
          unless callback.respond_to?(:arity)
            raise InvalidClientOptionError,
                  "Pub/Sub: callback must respond to #arity, got: #{callback.class}"
          end
        end
        raise InvalidClientOptionError, "Pub/Sub context: requires a callback" if callback.nil? && !context.nil?

        new(callback: callback, context: context)
      end

      # @param callback [Proc, Method, nil] invoked with the message instead of
      #   queueing it. A callback whose arity is exactly `1` receives `(message)`;
      #   every other arity receives `(message, context)`, including two-argument
      #   callbacks and variadic procs. It must answer `#arity`, which `make`
      #   enforces, so a bare object defining only `#call` is not accepted.
      # @param context [Object, nil] second argument for a callback whose arity
      #   is not 1.
      def initialize(callback: nil, context: nil)
        @callback = callback
        @context = context
        @message_queue = Thread::Queue.new
        @closed = false

        @ffi_handler = build_ffi_handler
        @callback_thread = start_callback_thread if callback
      end

      attr_reader :ffi_handler

      # @return [Boolean] whether messages go to a callback rather than the queue.
      def callback_mode?
        !@callback.nil?
      end

      def pop
        check_callback!

        @message_queue.pop
      end

      def try_pop
        check_callback!

        @message_queue.pop(true)
      rescue ThreadError
        # TODO: Log debug here
        nil
      end

      def close
        @closed = true
        @message_queue.close
        # A user callback may try to close, which would be from the callback_thread, and a thread cannot join on itself.
        @callback_thread&.join unless Thread.current == @callback_thread
      end

      private

      # Handling user callback on a separate threads. This avoids having long running callbacks
      # taking up the GVL and locking up the Ruby runtime.
      def start_callback_thread
        Thread.new do
          while (message = @message_queue.pop)
            break if @closed

            begin
              @callback.arity == 1 ? @callback.call(message) : @callback.call(message, @context)
            rescue StandardError
              # TODO: Log user callback errors
            end
          end
        end
      end

      def check_callback!
        return unless callback_mode?

        raise InvalidClientOptionError, "Pub/Sub callback was configured. Inline Pub/Sub reads are unavailable."
      end

      # Builds the proc handed to the FFI.
      #
      # Runs on a Rust thread the Ruby runtime did not create, on a single push
      # worker, with the GVL borrowed. Keep it thin: copy out, enqueue, return.
      # No user code, no FFI re-entry, no blocking I/O -- anything slow here
      # stalls every message behind it. The pointers are freed when it returns,
      # so the copy has to happen synchronously.
      #
      # The reads are length-driven so a payload with an embedded NUL survives.
      def build_ffi_handler
        lambda do |_client_ptr, kind, message_ptr, message_size, channel_ptr, channel_size, pattern_ptr, pattern_size|
          next unless PushKind::MESSAGE_KINDS.include?(kind)
          next if @closed

          pattern = pattern_ptr.null? ? nil : pattern_ptr.read_string(pattern_size)
          message = message_ptr.read_string(message_size)
          payload = PubSubMessage.new(message, channel_ptr.read_string(channel_size), pattern)
          @message_queue.push(payload)
        rescue StandardError
          # TODO: Log the swallowed error once a logger binding exists.
          nil
        end
      end
    end
  end
end
