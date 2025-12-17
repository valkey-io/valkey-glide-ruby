# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands related to Valkey Functions.
    #
    # @see https://valkey.io/commands/#scripting
    #
    module FunctionCommands
      # Delete a library and all its functions.
      #
      # @example Delete a library
      #   valkey.function_delete("mylib")
      #     # => "OK"
      #
      # @param [String] library_name the library name to delete
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/function-delete/
      def function_delete(library_name)
        send_command(RequestType::FUNCTION_DELETE, [library_name])
      end

      # Return the serialized payload of loaded libraries.
      #
      # @example Dump all libraries
      #   valkey.function_dump
      #     # => <binary string>
      #
      # @return [String] the serialized payload
      #
      # @see https://valkey.io/commands/function-dump/
      def function_dump
        send_command(RequestType::FUNCTION_DUMP)
      end

      # Delete all libraries.
      #
      # @example Flush all libraries
      #   valkey.function_flush
      #     # => "OK"
      # @example Flush all libraries asynchronously
      #   valkey.function_flush(async: true)
      #     # => "OK"
      # @example Flush all libraries synchronously
      #   valkey.function_flush(sync: true)
      #     # => "OK"
      #
      # @param [Boolean] async flush asynchronously
      # @param [Boolean] sync flush synchronously
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/function-flush/
      def function_flush(async: false, sync: false)
        args = []

        if async
          args << "ASYNC"
        elsif sync
          args << "SYNC"
        end

        send_command(RequestType::FUNCTION_FLUSH, args)
      end

      # Kill a function that is currently executing.
      #
      # @example Kill a running function
      #   valkey.function_kill
      #     # => "OK"
      #
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/function-kill/
      def function_kill
        send_command(RequestType::FUNCTION_KILL)
      end

      # Return information about the functions and libraries.
      #
      # @example List all libraries
      #   valkey.function_list
      #     # => [{"library_name" => "mylib", "engine" => "LUA", ...}]
      # @example List libraries matching a pattern
      #   valkey.function_list(library_name: "mylib*")
      #     # => [{"library_name" => "mylib", ...}]
      # @example List libraries with code
      #   valkey.function_list(with_code: true)
      #     # => [{"library_name" => "mylib", "library_code" => "...", ...}]
      #
      # @param [String] library_name filter by library name pattern
      # @param [Boolean] with_code include the library code in the response
      # @return [Array<Hash>] array of library information
      #
      # @see https://valkey.io/commands/function-list/
      def function_list(library_name: nil, with_code: false)
        args = []

        if library_name
          args << "LIBRARYNAME"
          args << library_name
        end

        args << "WITHCODE" if with_code

        send_command(RequestType::FUNCTION_LIST, args)
      end

      # Load a library to Valkey.
      #
      # @example Load a library
      #   code = "#!lua name=mylib\nvalkey.register_function('myfunc', function(keys, args) return args[1] end)"
      #   valkey.function_load(code)
      #     # => "mylib"
      # @example Load a library, replacing if exists
      #   valkey.function_load(code, replace: true)
      #     # => "mylib"
      #
      # @param [String] function_code the source code
      # @param [Boolean] replace replace the library if it exists
      # @return [String] the library name that was loaded
      #
      # @see https://valkey.io/commands/function-load/
      def function_load(function_code, replace: false)
        args = []
        args << "REPLACE" if replace
        args << function_code

        send_command(RequestType::FUNCTION_LOAD, args)
      end

      # Restore libraries from a payload.
      #
      # @example Restore libraries
      #   payload = valkey.function_dump
      #   valkey.function_restore(payload)
      #     # => "OK"
      # @example Restore libraries with FLUSH policy
      #   valkey.function_restore(payload, policy: "FLUSH")
      #     # => "OK"
      # @example Restore libraries with APPEND policy
      #   valkey.function_restore(payload, policy: "APPEND")
      #     # => "OK"
      # @example Restore libraries with REPLACE policy
      #   valkey.function_restore(payload, policy: "REPLACE")
      #     # => "OK"
      #
      # @param [String] serialized_value the serialized payload from FUNCTION DUMP
      # @param [String] policy the restore policy: "FLUSH", "APPEND", or "REPLACE"
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/function-restore/
      def function_restore(serialized_value, policy: nil)
        args = [serialized_value]

        args << policy.to_s.upcase if policy

        send_command(RequestType::FUNCTION_RESTORE, args)
      end

      # Return information about the function that's currently running.
      #
      # @example Get function stats
      #   valkey.function_stats
      #     # => {"running_script" => {...}, "engines" => {...}}
      #
      # @return [Hash] function execution statistics
      #
      # @see https://valkey.io/commands/function-stats/
      def function_stats
        send_command(RequestType::FUNCTION_STATS)
      end

      # Invoke a function.
      #
      # @example Call a function
      #   valkey.fcall("myfunc", keys: ["key1"], args: ["arg1"])
      #     # => <function result>
      # @example Call a function without keys
      #   valkey.fcall("myfunc", args: ["arg1", "arg2"])
      #     # => <function result>
      #
      # @param [String] function the function name
      # @param [Array<String>] keys the keys to pass to the function
      # @param [Array<String>] args the arguments to pass to the function
      # @return [Object] the function result
      #
      # @see https://valkey.io/commands/fcall/
      def fcall(function, keys: [], args: [])
        command_args = [function, keys.size] + keys + args
        send_command(RequestType::FCALL, command_args)
      end

      # Invoke a read-only function.
      #
      # @example Call a read-only function
      #   valkey.fcall_ro("myfunc", keys: ["key1"], args: ["arg1"])
      #     # => <function result>
      #
      # @param [String] function the function name
      # @param [Array<String>] keys the keys to pass to the function
      # @param [Array<String>] args the arguments to pass to the function
      # @return [Object] the function result
      #
      # @see https://valkey.io/commands/fcall_ro/
      def fcall_ro(function, keys: [], args: [])
        command_args = [function, keys.size] + keys + args
        send_command(RequestType::FCALL_READ_ONLY, command_args)
      end

      # Control function registry (convenience method).
      #
      # @example Delete a library
      #   valkey.function(:delete, "mylib")
      #     # => "OK"
      # @example Dump all libraries
      #   valkey.function(:dump)
      #     # => <binary string>
      # @example Flush all libraries
      #   valkey.function(:flush)
      #     # => "OK"
      # @example Kill a running function
      #   valkey.function(:kill)
      #     # => "OK"
      # @example List all libraries
      #   valkey.function(:list)
      #     # => [...]
      # @example Load a library
      #   valkey.function(:load, code)
      #     # => "mylib"
      # @example Restore libraries
      #   valkey.function(:restore, payload)
      #     # => "OK"
      # @example Get function stats
      #   valkey.function(:stats)
      #     # => {...}
      #
      # @param [String, Symbol] subcommand the subcommand (delete, dump, flush, kill, list, load, restore, stats)
      # @param [Array] args arguments for the subcommand
      # @param [Hash] options options for the subcommand
      # @return [Object] depends on subcommand
      def function(subcommand, *args, **options)
        subcommand = subcommand.to_s.downcase

        if args.empty? && options.empty?
          send("function_#{subcommand}")
        elsif options.empty?
          send("function_#{subcommand}", *args)
        else
          send("function_#{subcommand}", *args, **options)
        end
      end
    end
  end
end
