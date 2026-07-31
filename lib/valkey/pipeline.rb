# frozen_string_literal: true

class Valkey
  class Pipeline
    include Commands

    # SUBSCRIBE-shape commands drive a persistent connection state
    # (the client stays subscribed and reads push messages asynchronously)
    # which is fundamentally incompatible with pipelining/transactions.
    # If we let them into the batch the server side transitions the shared
    # connection into subscribe-state and every subsequent non-pubsub command
    # fails with "only (P|S)SUBSCRIBE / ... allowed in this context".
    # Reject them at enqueue time before any FFI dispatch so callers get a
    # clear, actionable error and the client stays usable.
    SUBSCRIBE_SHAPE_COMMANDS = [
      RequestType::SUBSCRIBE,
      RequestType::UNSUBSCRIBE,
      RequestType::PSUBSCRIBE,
      RequestType::PUNSUBSCRIBE,
      RequestType::SSUBSCRIBE,
      RequestType::SUNSUBSCRIBE
    ].freeze

    SUBSCRIBE_SHAPE_ERROR = <<~MSG.strip.tr("\n", " ")
      SUBSCRIBE-shape commands cannot be used inside pipelined { ... } —
      subscribe manages a persistent connection state that is incompatible
      with pipelining. Call subscribe directly on the client instead.
    MSG

    attr_reader :commands, :futures

    def initialize
      @commands = []
      @futures = []
      # Keep transactional state consistent with the main client so that
      # helpers like `multi`/`exec` can safely consult `@in_multi`.
      @in_multi = false
    end

    def send_command(command_type, command_args = [], &block)
      raise CommandError, SUBSCRIBE_SHAPE_ERROR if SUBSCRIBE_SHAPE_COMMANDS.include?(command_type)

      @commands << [command_type, command_args, block]
      future = Future.new(command_type, command_args)
      @futures << future
      future
    end

    # @api private - called by Valkey#pipelined / the block form of #multi
    # once send_batch_commands' final results are available. Purely
    # positional, mirroring send_batch_commands' own per-command block
    # re-application - safe for both the real-batch and the sequential
    # MULTI/EXEC/DISCARD fallback branch, since both produce the same
    # shape/order of results.
    #
    # `results` is `nil` when a watched key was modified, aborting the whole
    # transaction server-side before any queued command actually ran - none
    # of these futures were ever really resolved, so treat it the same as
    # abort_futures! instead of raising NoMethodError on a nil index.
    def resolve_futures!(results)
      return abort_futures! if results.nil?

      @futures.each_with_index { |future, i| future._set(results[i]) }
    end

    # @api private - called when an exception escapes pipelined/multi before
    # resolve_futures! ran, so every still-unresolved future raises a clear
    # FutureAborted instead of hanging on FutureNotReady forever.
    def abort_futures!
      @futures.each(&:_abort!)
    end
  end
end
