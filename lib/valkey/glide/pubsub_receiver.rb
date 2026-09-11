# frozen_string_literal: true

class Valkey
  module Glide
    # Receives Pub/Sub pushes from the native layer and delivers them in one of
    # two mutually exclusive modes: queued for inline reads, or handed straight
    # to a user callback.
    #
    # @api private
    class PubSubReceiver
      # @param callback [#call, nil] invoked with the message instead of queueing
      #   it. A callback of `arity == 1` receives `(message)`; any other arity
      #   receives `(message, context)`. Note that a lambda and a non-lambda
      #   proc differ here: `->(message) {}` has arity `1`, while
      #   `proc { |message| }` has arity `-1` and so is called with both
      #   arguments.
      # @param context [Object, nil] second argument for a callback whose arity
      #   is not 1.
      def initialize(callback: nil, context: nil)
        @callback = callback
        @context = context
        @message_queue = Thread::Queue.new

        @ffi_handler = build_ffi_handler
      end

      attr_reader :ffi_handler

      # @return [Boolean] whether messages go to a callback rather than the queue.
      def callback_mode?
        !@callback.nil?
      end

      def pop
        ensure_inline_reads_available!

        @message_queue.pop
      end

      def try_pop
        ensure_inline_reads_available!

        @message_queue.pop(true)
      rescue ThreadError
        # TODO: Log debug here
        nil
      end

      def close
        @message_queue.close
      end

      private

      # In callback mode nothing ever reaches the queue, so a blocking pop would
      # wait forever.
      def ensure_inline_reads_available!
        return unless callback_mode?

        raise CommandError, "Inline Pub/Sub reads are unavailable when a Pub/Sub callback is configured"
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
          next unless Commands::PubSubCommands::PushKind::MESSAGE_KINDS.include?(kind)

          pattern = pattern_ptr.null? ? nil : pattern_ptr.read_string(pattern_size)
          message = message_ptr.read_string(message_size)
          deliver(
            Commands::PubSubCommands::Message.new(message, channel_ptr.read_string(channel_size), pattern)
          )
        rescue StandardError
          # TODO: Log the swallowed error once a logger binding exists.
          nil
        end
      end

      # Single delivery point, so push mode is added by branching here and
      # nothing else changes.
      def deliver(message)
        return @message_queue.push(message) unless @callback

        # User code on the push thread, against the handler's own contract: a
        # slow or blocking callback stalls every message behind it, and
        # re-entering the client from here can deadlock.
        @callback.arity == 1 ? @callback.call(message) : @callback.call(message, @context)
      end
    end
  end
end
