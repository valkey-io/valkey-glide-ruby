# frozen_string_literal: true

class Valkey
  module Commands
    # this module contains commands related to list data type.
    #
    # @see https://valkey.io/commands/#scripting
    #
    module ScriptingCommands
      # Control remote script registry.
      #
      # @example Load a script
      #   sha = valkey.script(:load, "return 1")
      #     # => <sha of this script>
      # @example Check if a script exists
      #   valkey.script(:exists, sha)
      #     # => true
      # @example Check if multiple scripts exist
      #   valkey.script(:exists, [sha, other_sha])
      #     # => [true, false]
      # @example Flush the script registry
      #   valkey.script(:flush)
      #     # => "OK"
      # @example Kill a running script
      #   valkey.script(:kill)
      #     # => "OK"
      #
      # @param [String] subcommand e.g. `exists`, `flush`, `load`, `kill`
      # @param [Array<String>] args depends on subcommand
      # @return [String, Boolean, Array<Boolean>, ...] depends on subcommand
      #
      # @see #eval
      # @see #evalsha
      def script(subcommand, args = nil, options: {})
        subcommand = subcommand.to_s.downcase

        if args.nil?
          send("script_#{subcommand}", **options)
        else
          send("script_#{subcommand}", args)
        end

        # if subcommand == "exists"
        #   arg = args.first
        #
        #   send_command([:script, :exists, arg]) do |reply|
        #     reply = reply.map { |r| Boolify.call(r) }
        #
        #     if arg.is_a?(Array)
        #       reply
        #     else
        #       reply.first
        #     end
        #   end
        # else
        #   send_command([:script, subcommand] + args)
        # end
      end

      def script_flush(sync: false, async: false)
        args = []

        if async
          args << "async"
        elsif sync
          args << "sync"
        end

        send_command(RequestType::SCRIPT_FLUSH, args)
      end

      def script_exists(args)
        send_command(RequestType::SCRIPT_EXISTS, Array(args)) do |reply|
          if args.is_a?(Array)
            reply
          else
            reply.first
          end
        end
      end

      def script_kill
        send_command(RequestType::SCRIPT_KILL)
      end

      def script_load(script)
        script = script.is_a?(Array) ? script.first : script

        buf = FFI::MemoryPointer.new(:char, script.bytesize)
        buf.put_bytes(0, script)

        result = Bindings.store_script(buf, script.bytesize)

        hash_buffer = Bindings::ScriptHashBuffer.new(result)
        hash_buffer[:ptr].read_string(hash_buffer[:len])
      end

      # Execute a Lua script on the server.
      #
      # @param [String] script the Lua script to execute
      # @param [Array<String>] keys array of key names that the script will access
      # @param [Array<Object>] args array of arguments to pass to the script
      # @return [Object] the result of the script execution
      # @raise [ArgumentError] if script is empty
      # @raise [CommandError] if script execution fails
      #
      # @example Execute a simple script
      #   valkey.eval("return 1")
      #     # => 1
      # @example Execute script with keys and arguments
      #   valkey.eval("return KEYS[1] .. ARGV[1]", keys: ["mykey"], args: ["myarg"])
      #     # => "mykeynyarg"
      # @example Execute script with multiple keys and arguments
      #   valkey.eval("return #KEYS + #ARGV", keys: ["key1", "key2"], args: ["arg1", "arg2", "arg3"])
      #     # => 5
      # @example Execute script that returns different data types
      #   valkey.eval("return {1, 'hello', true, nil}")
      #     # => [1, "hello", true, nil]
      # Since the eval is not available in the rust backend
      # using the load and invoke script
      def eval(script, keys: [], args: [])
        # Validate script parameter
        raise ArgumentError, "script must be a string" unless script.is_a?(String)
        raise ArgumentError, "script cannot be empty" if script.empty?

        # Validate and convert keys and args to strings
        begin
          keys = Array(keys).map(&:to_s)
          args = Array(args).map(&:to_s)
        rescue StandardError => e
          raise ArgumentError, "failed to convert keys or args to strings: #{e.message}"
        end

        # Load script to get SHA1 hash, then execute via invoke_script
        sha = script_load(script)
        invoke_script(sha, keys: keys, args: args)
      end

      # Execute a cached Lua script by its SHA1 hash.
      #
      # @param [String] sha the SHA1 hash of the script to execute
      # @param [Array<String>] keys array of key names that the script will access
      # @param [Array<Object>] args array of arguments to pass to the script
      # @return [Object] the result of the script execution
      # @raise [ArgumentError] if SHA1 hash format is invalid
      # @raise [CommandError] if script is not found or execution fails
      #
      # @example Execute a cached script
      #   sha = valkey.script_load("return 1")
      #   valkey.evalsha(sha)
      #     # => 1
      # @example Execute cached script with parameters
      #   script = "return KEYS[1] .. ':' .. ARGV[1]"
      #   sha = valkey.script_load(script)
      #   valkey.evalsha(sha, keys: ["user"], args: ["123"])
      #     # => "user:123"
      # @example Handle script not found error
      #   begin
      #     valkey.evalsha("nonexistent_sha", keys: [], args: [])
      #   rescue Valkey::CommandError => e
      #     puts "Script not found: #{e.message}"
      #   end
      # Since evalsha is not available in rust backend
      # using invoke script
      def evalsha(sha, keys: [], args: [])
        # Validate SHA1 hash parameter
        raise ArgumentError, "sha1 hash must be a string" unless sha.is_a?(String)
        raise ArgumentError, "sha1 hash must be a 40-character hexadecimal string" unless valid_sha1?(sha)

        # Validate and convert keys and args to strings
        begin
          keys = Array(keys).map(&:to_s)
          args = Array(args).map(&:to_s)
        rescue StandardError => e
          raise ArgumentError, "failed to convert keys or args to strings: #{e.message}"
        end

        # Execute cached script via invoke_script
        invoke_script(sha, keys: keys, args: args)
      end

      def invoke_script(script, args: [], keys: [])
        arg_ptrs, arg_lens = build_command_args(args)
        keys_ptrs, keys_lens = build_command_args(keys)

        route = ""
        route_buf = FFI::MemoryPointer.from_string(route)

        sha = FFI::MemoryPointer.new(:char, script.bytesize + 1)
        sha.put_bytes(0, script)

        res = Bindings.invoke_script(
          @connection,
          0,
          sha,
          keys.size,
          keys_ptrs,
          keys_lens,
          args.size,
          arg_ptrs,
          arg_lens,
          route_buf,
          route.bytesize
        )

        convert_response(res)
      end

      private

      # Validate SHA1 hash format (40-character hexadecimal string)
      def valid_sha1?(sha)
        sha.is_a?(String) && sha.length == 40 && sha.match?(/\A[a-fA-F0-9]{40}\z/)
      end
    end
  end
end
