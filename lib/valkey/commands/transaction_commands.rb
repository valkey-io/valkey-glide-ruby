# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands related to transactions.
    #
    # @see https://valkey.io/commands/#transactions
    #
    module TransactionCommands
      # Distinguishes "exception: not passed" from any real boolean, so the
      # no-block branch of #multi can raise instead of silently ignoring it.
      NO_EXCEPTION_KWARG = Object.new
      private_constant :NO_EXCEPTION_KWARG

      # Mark the start of a transaction block.
      #
      # @example With a block
      #   valkey.multi do |multi|
      #     multi.set("key", "value")
      #     multi.incr("counter")
      #   end # => ["OK", 6]
      #
      # @yield [multi] the commands that are called inside this block are cached
      #   locally (no server round-trip per command) and sent to the server as a
      #   single atomic batch once the block returns - GLIDE wraps them in a real
      #   MULTI/EXEC transaction internally. If the block raises, nothing has been
      #   sent to the server yet, so the exception simply propagates - there is no
      #   transaction to discard. Each in-block command call returns a
      #   {Valkey::Future} immediately; capture it and call `#value` on it once
      #   the block has returned to read that command's own reply:
      #
      #   @example Capturing a per-command reply
      #     future = nil
      #     valkey.multi do |multi|
      #       future = multi.incr("counter")
      #       multi.expire("counter", 60)
      #     end
      #     future.value # => 6
      #
      #   With `exception: true` (the default, matching redis-rb), a runtime
      #   error from a queued command (e.g. WRONGTYPE) raises and the array
      #   is discarded, even though the server already committed the other
      #   commands. Pass `exception: false` to get the array back instead,
      #   with the failing command's slot holding a {Valkey::CommandError}.
      #   A queue-time abort (e.g. a syntax/arity error) still always raises
      #   {Valkey::ExecAbortError}, since nothing ran in that case.
      #
      #   `exception:` only applies here - the imperative `multi` (no
      #   block) / `#exec` pair has no equivalent control and raises
      #   {ArgumentError} if passed one.
      # @yieldparam [Valkey::Pipeline] multi collects the block's commands
      # @param exception [Boolean] see above; a valkey-glide-ruby-specific
      #   extension - redis-rb's `multi` has no equivalent kwarg.
      #
      # @return [Array<...>]
      #   - an array with replies
      #
      # @see #watch
      # @see #unwatch
      def multi(exception: NO_EXCEPTION_KWARG)
        if block_given?
          exception = true if exception.equal?(NO_EXCEPTION_KWARG)
          pipeline = Pipeline.new

          begin
            yield pipeline

            return [] if pipeline.commands.empty?

            results = send_batch_commands(pipeline.commands, exception: exception, is_atomic: true)
            pipeline.resolve_futures!(results)
            results
          rescue StandardError
            pipeline.abort_futures!
            raise
          end
        else
          unless exception.equal?(NO_EXCEPTION_KWARG)
            raise ArgumentError, "exception: is only supported for multi's block form"
          end

          start_multi
          self
        end
      end

      # Watch the given keys to determine execution of the MULTI/EXEC block.
      #
      # Using a block is optional, but is recommended for automatic cleanup.
      #
      # An `#unwatch` is automatically issued if an exception is raised within the
      # block that is a subclass of StandardError and is not a ConnectionError.
      #
      # @example With a block
      #   valkey.watch("key") do
      #     if valkey.get("key") == "some value"
      #       valkey.multi do |multi|
      #         multi.set("key", "other value")
      #         multi.incr("counter")
      #       end
      #     else
      #       valkey.unwatch
      #     end
      #   end
      #     # => ["OK", 6]
      #
      # @example Without a block
      #   valkey.watch("key")
      #     # => "OK"
      #
      # @param [String, Array<String>] keys one or more keys to watch
      # @return [Object] if using a block, returns the return value of the block
      # @return [String] if not using a block, returns `"OK"`
      #
      # @see #unwatch
      # @see #multi
      # @see #exec
      def watch(*keys)
        keys.flatten!(1)
        res = send_command(RequestType::WATCH, keys)

        if block_given?
          begin
            yield(self)
          rescue ConnectionError
            raise
          rescue StandardError
            unwatch
            raise
          end
        else
          res
        end
      end

      # Forget about all watched keys.
      #
      # @return [String] `"OK"`
      #
      # @see #watch
      # @see #multi
      def unwatch
        send_command(RequestType::UNWATCH)
      end

      # Execute all commands issued after MULTI.
      #
      # Only call this method when `#multi` was called **without** a block.
      #
      # @return [nil, Array<...>]
      #   - when commands were not executed, `nil`
      #   - when commands were executed, an array with their replies
      #
      # @see #multi
      # @see #discard
      def exec
        if @in_multi
          queued_commands = @queued_commands
          begin
            begin
              result = send_command(RequestType::EXEC)
              # If EXEC returns an error object (from array), it's already handled
              result.is_a?(Array) ? reconvert_queued_replies(result, queued_commands) : result
            rescue CommandError => e
              # If EXEC itself raises an error (like when transaction is aborted),
              # return an array with the error to match expected behavior in tests
              [e]
            end
          ensure
            @in_multi = false
            @queued_commands = []
          end
        else
          # When EXEC is called without a preceding MULTI the server returns an
          # error. The lint tests allow clients to either raise or return nil;
          # we normalize this to simply return nil.
          begin
            send_command(RequestType::EXEC)
          rescue CommandError
            nil
          end
        end
      end

      # Discard all commands issued after MULTI.
      #
      # @return [String] `"OK"`
      #
      # @see #multi
      # @see #exec
      def discard
        send_command(RequestType::DISCARD)
      rescue CommandError
        # DISCARD without MULTI is treated similarly to EXEC without MULTI:
        # ignore the server error and return nil.
        nil
      ensure
        @in_multi = false
        @queued_commands = []
      end

      # Commands the server coerces to boolean by name, but which arrive as raw 0/1
      # inside an EXEC array (glide-core keys coercion on the executed command - EXEC -
      # not the queued ones). Listed here so #reconvert_queued_replies can restore it.
      #
      # This is glide-core's boolean table (`value_conversion.rs::expected_type_for_cmd`)
      # minus commands whose Ruby method passes its own conversion block - those are
      # handled by the `if block` branch below. Only block-less RequestTypes belong here.
      #
      # SETNX is absent by design: glide-core doesn't treat it as boolean (name-keyed
      # coercion can't distinguish it from a raw `customCommand(["SETNX", ...])`), so
      # `setnx` passes `&Utils::Boolify` itself (string_commands.rb) - covered by `if block`.
      BOOLEAN_REQUEST_TYPES = [
        RequestType::EXPIRE, RequestType::EXPIRE_AT, RequestType::PEXPIRE, RequestType::PEXPIRE_AT,
        RequestType::PERSIST, RequestType::SISMEMBER, RequestType::S_MOVE, RequestType::PFADD,
        RequestType::RENAME_NX, RequestType::MOVE, RequestType::COPY, RequestType::MSET_NX
      ].freeze

      private

      # Re-applies each queued command's reply conversion to EXEC's raw array: its own
      # block if it had one, else Boolify for a BOOLEAN_REQUEST_TYPES command. Mirrors
      # what redis-rb's Futures do (each remembers its conversion and re-applies it once
      # EXEC resolves); glide's queued commands have no such memory, so we restore it here.
      def reconvert_queued_replies(result, queued_commands)
        return result unless result.size == queued_commands.size

        result.each_with_index.map do |value, i|
          # Leave an inline error slot alone - Boolify would otherwise
          # coerce it to `true` (mirrors the same guard in
          # Valkey#send_batch_commands).
          next value if value.is_a?(CommandError)

          command_type, _args, block = queued_commands[i]
          if block
            block.call(value)
          elsif BOOLEAN_REQUEST_TYPES.include?(command_type)
            Utils::Boolify.call(value)
          else
            value
          end
        end
      end

      # Start a MULTI block if one isn't already active.
      #
      # This mirrors the behaviour of popular Valkey/Redis clients where
      # nested MULTI calls are effectively ignored by the client.
      def start_multi
        return if @in_multi

        send_command(RequestType::MULTI)
        @in_multi = true
        @queued_commands = []
      end
    end
  end
end
