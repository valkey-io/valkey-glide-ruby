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
      #   and written to the server upon returning from it
      # @yieldparam [Valkey] multi `self`
      #
      # @return [Array<...>]
      #   - an array with replies
      #
      # @see #watch
      # @see #unwatch
      def multi
        if block_given?
          begin
            @in_multi_block = true
            start_multi
            yield(self)
            exec
          rescue StandardError
            discard
            raise
          ensure
            @in_multi_block = false
          end
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
          begin
            begin
              result = send_command(RequestType::EXEC)
              # If EXEC returns an error object (from array), it's already handled
              result
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

      private

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
