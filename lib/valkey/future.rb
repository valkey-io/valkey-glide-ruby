# frozen_string_literal: true

class Valkey
  # Raised by Future#value when the pipeline/multi block has not finished
  # executing yet (e.g. called from inside the block itself).
  class FutureNotReady < BaseError
    def initialize(msg = "Value will be available once the pipeline executes.")
      super
    end
  end

  # Raised by Future#value when the owning pipeline/multi block raised (or a
  # sequential MULTI/EXEC/DISCARD fallback batch failed partway through)
  # before this command's slot could ever be resolved. Distinct from
  # FutureNotReady (still a subclass, so `rescue FutureNotReady` still catches
  # it) to give a much clearer diagnostic than "not ready yet" for something
  # that in fact will never become ready.
  class FutureAborted < FutureNotReady
    def initialize(msg = "This pipeline/multi block raised (or a sequential " \
                         "fallback batch failed partway through) before this " \
                         "command's result could be resolved.")
      super
    end
  end

  # A placeholder for the reply to a command queued inside Valkey#pipelined
  # or the block form of Valkey::Commands::TransactionCommands#multi.
  #
  # Deliberately a plain Object, not BasicObject (unlike redis-rb's
  # Redis::Future): #value is always called explicitly by callers, never as a
  # transparent proxy, so BasicObject's stripped-down method surface buys
  # nothing here.
  #
  # Coercion (Utils::Boolify, etc.) is intentionally not duplicated here: by
  # the time Pipeline#resolve_futures! calls #_set, send_batch_commands has
  # already applied it to the corresponding results[i].
  class Future
    NOT_READY = Object.new.freeze
    private_constant :NOT_READY

    def initialize(command_type, command_args)
      @command_type = command_type
      @command_args = command_args
      @object = NOT_READY
      @aborted = false
    end

    # @api private
    def _set(object)
      @object = object
    end

    # @api private
    def _abort!
      @aborted = true if @object.equal?(NOT_READY)
    end

    # @return [Boolean] whether #value can be called right now without
    #   raising FutureNotReady/FutureAborted.
    def ready?
      !@aborted && !@object.equal?(NOT_READY)
    end

    # @return [Object] the resolved reply, already coerced the same way a
    #   live (non-pipelined) call to the same command would be.
    # @raise [FutureAborted] if the owning pipeline never got to resolve this
    #   command (block raised, or the batch failed partway through)
    # @raise [FutureNotReady] if called before the pipeline/multi block has
    #   returned and its batch has been sent
    # @raise [CommandError] if this slot's reply was itself an inline error
    #   (e.g. WRONGTYPE inside a batch) - matches Valkey#convert_response's
    #   "no rollback on runtime error" semantics.
    def value
      raise FutureAborted if @aborted
      raise FutureNotReady if @object.equal?(NOT_READY)
      raise @object if @object.is_a?(StandardError)

      @object
    end

    def inspect
      "#<Valkey::Future #{@command_type.inspect} #{@command_args.inspect}>"
    end
  end
end
