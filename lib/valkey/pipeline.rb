# frozen_string_literal: true

class Valkey
  class Pipeline
    include Commands

    attr_reader :commands, :futures

    def initialize
      @commands = []
      @futures = []
      # Keep transactional state consistent with the main client so that
      # helpers like `multi`/`exec` can safely consult `@in_multi`.
      @in_multi = false
    end

    # `route:` is accepted and ignored. It exists for signature parity with
    # Valkey#send_command, since any command reaching a pipeline through #call
    # passes it, but a batch is dispatched as one unit so a per-command route
    # cannot be honored. Batch-level routing is tracked in issue #137.
    def send_command(command_type, command_args = [], route: nil, &block) # rubocop:disable Lint/UnusedMethodArgument
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
