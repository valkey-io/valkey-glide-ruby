# frozen_string_literal: true

class Valkey
  # TODO: Pipeline/Multi routing is to be implemented.
  # See https://github.com/valkey-io/valkey-glide-ruby/issues/137
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
    def send_command(command_type, command_args = [], route: nil, &block)
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

    # ---------------------------------------------------------------------
    # Signature overrides that strip the `route:` kwarg from methods that
    # carry it in the shared Commands module. Individual pipelined commands
    # cannot be routed.
    #
    # TODO: Pipeline level routing to be added in the future.
    # See https://github.com/valkey-io/valkey-glide-ruby/issues/137
    # ---------------------------------------------------------------------

    # rubocop:disable Lint/UselessMethodDefinition
    # server_commands
    def bgrewriteaof
      super
    end

    def bgsave
      super
    end

    def config_get(*args)
      super
    end

    def config_set(*args)
      super
    end

    def config_resetstat
      super
    end

    def config_rewrite
      super
    end

    def dbsize
      super
    end

    def flushall(options = nil)
      super
    end

    def flushdb(options = nil)
      super
    end

    def info(cmd = nil)
      super
    end

    def lastsave
      super
    end

    def save
      super
    end

    def time
      super
    end

    def lolwut(version = nil)
      super
    end

    # function_commands
    def function_delete(library_name)
      super
    end

    def function_dump
      super
    end

    def function_flush(async: false, sync: false)
      super
    end

    def function_kill
      super
    end

    def function_list(library_name: nil, with_code: false)
      super
    end

    def function_load(function_code, replace: false)
      super
    end

    def function_restore(serialized_value, policy: nil)
      super
    end

    def function_stats
      super
    end

    # connection_commands
    def ping(message = nil)
      super
    end

    def echo(value)
      super
    end

    def client_id
      super
    end

    def client_unpause
      super
    end

    # generic_commands
    def randomkey
      super
    end

    def call(*argv, **kwargs)
      if kwargs.key?(:route)
        raise ArgumentError, "Not supported: :route is not supported for individual pipelined commands"
      end

      super
    end

    def call_v(argv)
      super
    end
    # rubocop:enable Lint/UselessMethodDefinition

    def subscribe(*_channels, timeout_ms: 0)
      raise CommandError, "subscribe is not supported in a pipeline or transaction"
    end

    def unsubscribe(*_channels, timeout_ms: 0)
      raise CommandError, "unsubscribe is not supported in a pipeline or transaction"
    end

    def psubscribe(*_patterns, timeout_ms: 0)
      raise CommandError, "psubscribe is not supported in a pipeline or transaction"
    end

    def punsubscribe(*_patterns, timeout_ms: 0)
      raise CommandError, "punsubscribe is not supported in a pipeline or transaction"
    end

    def ssubscribe(*_channels, timeout_ms: 0)
      raise CommandError, "ssubscribe is not supported in a pipeline or transaction"
    end

    def sunsubscribe(*_channels, timeout_ms: 0)
      raise CommandError, "sunsubscribe is not supported in a pipeline or transaction"
    end

    def subscribe_lazy(*_channels)
      raise CommandError, "subscribe_lazy is not supported in a pipeline or transaction"
    end

    def unsubscribe_lazy(*_channels)
      raise CommandError, "unsubscribe_lazy is not supported in a pipeline or transaction"
    end

    def psubscribe_lazy(*_patterns)
      raise CommandError, "psubscribe_lazy is not supported in a pipeline or transaction"
    end

    def punsubscribe_lazy(*_patterns)
      raise CommandError, "punsubscribe_lazy is not supported in a pipeline or transaction"
    end

    def ssubscribe_lazy(*_channels)
      raise CommandError, "ssubscribe_lazy is not supported in a pipeline or transaction"
    end

    def sunsubscribe_lazy(*_channels)
      raise CommandError, "sunsubscribe_lazy is not supported in a pipeline or transaction"
    end

    def get_subscriptions
      raise CommandError, "get_subscriptions is not supported in a pipeline or transaction"
    end

    def get_pubsub_message
      raise CommandError, "get_pubsub_message is not supported in a pipeline or transaction"
    end

    def try_get_pubsub_message
      raise CommandError, "try_get_pubsub_message is not supported in a pipeline or transaction"
    end

    def pubsub_channels(_pattern = nil)
      raise CommandError, "pubsub_channels is not supported in a pipeline or transaction"
    end

    def pubsub_numpat
      raise CommandError, "pubsub_numpat is not supported in a pipeline or transaction"
    end

    def pubsub_numsub(*_channels)
      raise CommandError, "pubsub_numsub is not supported in a pipeline or transaction"
    end

    def pubsub_shardchannels(_pattern = nil)
      raise CommandError, "pubsub_shardchannels is not supported in a pipeline or transaction"
    end

    def pubsub_shardnumsub(*_channels)
      raise CommandError, "pubsub_shardnumsub is not supported in a pipeline or transaction"
    end
  end
end
