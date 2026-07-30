# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands related to transactions.
    #
    # @see https://valkey.io/commands/#transactions
    #
    module TransactionCommands
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
      #   transaction to discard.
      # @yieldparam [Valkey::Pipeline] multi collects the block's commands
      #
      # @return [Array<...>]
      #   - an array with replies
      #
      # @see #watch
      # @see #unwatch
      def multi
        if block_given?
          pipeline = Pipeline.new
          yield pipeline

          return [] if pipeline.commands.empty?

          send_batch_commands(pipeline.commands, exception: true, is_atomic: true)
        else
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

      # Commands whose reply is boolean when run standalone (via native return-type
      # coercion server-side), but arrives as a raw 0/1 integer inside an EXEC array,
      # since that coercion is keyed by the single command actually being run - which,
      # for a queued command, is EXEC itself, not the original command.
      #
      # This list mirrors glide-core's own Boolean-coercion table in
      # `value_conversion.rs::expected_type_for_cmd` (HEXISTS, HSETNX, EXPIRE, EXPIREAT,
      # PEXPIRE, PEXPIREAT, SISMEMBER, PERSIST, SMOVE, PFADD, RENAMENX, MOVE, COPY,
      # MSETNX, XGROUP DESTROY, XGROUP CREATECONSUMER) MINUS the commands whose Ruby
      # method already passes its own explicit conversion block (`hexists`/`hsetnx`
      # use `&Utils::Boolify`; `xgroup_destroy`/`xgroup_createconsumer` use a custom
      # bool->int block). Those are already handled correctly by the `if block`
      # branch below, before this list is even consulted - listing them here too
      # would be redundant, not wrong. Every RequestType below calls `send_command`
      # with NO block at all, so this static list is the only place their boolean-ness
      # is recorded.
      #
      # NOTE: SETNX is deliberately NOT in glide-core's coercion table (and so isn't
      # here as a "no block" entry either) - it's `redis-rb`-style boolean-ness only,
      # not something the server/`glide-core` treats as boolean, since coercion there
      # is keyed by command name alone and can't distinguish this dedicated RequestType
      # from a raw `customCommand(["SETNX", ...])` call, which other bindings' existing
      # contracts expect to keep returning a plain integer. `setnx`'s own Ruby method
      # passes `&Utils::Boolify` directly instead - see string_commands.rb - so it's
      # already covered by the `if block` branch, same as hexists/hsetnx.
      BOOLEAN_REQUEST_TYPES = [
        RequestType::EXPIRE, RequestType::EXPIRE_AT, RequestType::PEXPIRE, RequestType::PEXPIRE_AT,
        RequestType::PERSIST, RequestType::SISMEMBER, RequestType::S_MOVE, RequestType::PFADD,
        RequestType::RENAME_NX, RequestType::MOVE, RequestType::COPY, RequestType::MSET_NX
      ].freeze

      private

      # Re-applies each queued command's own reply conversion (e.g. `&Utils::Boolify`)
      # to EXEC's raw array, since redis-rb's Future-based design does the equivalent
      # (a Future remembers its conversion and re-applies it once EXEC resolves), but
      # queued commands here go through the plain single-command path with no such
      # memory - see BOOLEAN_REQUEST_TYPES above for the case with no explicit block.
      def reconvert_queued_replies(result, queued_commands)
        return result unless result.size == queued_commands.size

        result.each_with_index.map do |value, i|
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
