# frozen_string_literal: true

class Valkey
  module Glide
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

      def initialize
        @message_queue = Thread::Queue.new

        @ffi_handler = build_ffi_handler
      end

      attr_reader :ffi_handler

      def pop
        @message_queue.pop
      end

      def try_pop
        @message_queue.pop(true)
      rescue ThreadError
        # TODO: Log debug here
        nil
      end

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
      # The reads are length-driven so a payload with an embedded NUL survives.
      def build_ffi_handler
        lambda do |_client_ptr, kind, message_ptr, message_size, channel_ptr, channel_size, pattern_ptr, pattern_size|
          next unless PushKind::MESSAGE_KINDS.include?(kind)

          pattern = pattern_ptr.null? ? nil : pattern_ptr.read_string(pattern_size)
          message = message_ptr.read_string(message_size)
          deliver(
            PubSubMessage.new(message, channel_ptr.read_string(channel_size), pattern)
          )
        rescue StandardError
          # TODO: Log the swallowed error once a logger binding exists.
          nil
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
