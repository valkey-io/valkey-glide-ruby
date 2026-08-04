# frozen_string_literal: true

class Valkey
  module Commands
    # this module contains commands related to list data type.
    #
    # EVAL / EVALSHA / SCRIPT LOAD are dispatched as custom commands via #call
    # rather than through typed `send_command(RequestType::EVAL, ...)`. This is
    # not a style choice: glide-core defines those enum values but has no
    # `get_command()` arm for them, so typed dispatch fails outright with
    # "Couldn't fetch command type - ClientError". Cluster routing is unaffected
    # (redis-rs derives it from the wire command name, so EVAL still routes by
    # ThirdArgAfterKeyCount and SCRIPT LOAD still broadcasts to all nodes), but
    # OpenTelemetry spans are named "CustomCommand" instead of the command.
    # Once glide-core gains those arms, these can revert to typed dispatch -
    # EVAL_RO / EVALSHA_RO already have arms and could use it today; they go
    # through #call only to keep the family's behavior uniform.
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

      # Set the debug mode for subsequent scripts executed with EVAL.
      #
      # @param [String] mode debug mode: "YES", "SYNC", or "NO"
      # @return [String] "OK"
      #
      # @example Enable script debugging
      #   valkey.script_debug("YES")
      #     # => "OK"
      # @example Disable script debugging
      #   valkey.script_debug("NO")
      #     # => "OK"
      #
      # @see https://valkey.io/commands/script-debug/
      def script_debug(mode)
        send_command(RequestType::SCRIPT_DEBUG, [mode.to_s.upcase])
      end

      # Load a Lua script into the server's script cache without executing it.
      #
      # Sends a real `SCRIPT LOAD` to the server, so the returned SHA1 is
      # immediately usable by `evalsha` - including from a different client,
      # process, or worker. In cluster mode `SCRIPT LOAD` is routed to all
      # nodes, so the script is available whichever node a later `EVALSHA`
      # lands on.
      #
      # @param [String] script the Lua script to load
      # @return [String] the SHA1 hash of the script, as computed by the server
      #
      # @example
      #   sha = valkey.script_load("return 1")
      #   valkey.script_exists(sha)   # => true
      #
      # @see https://valkey.io/commands/script-load/
      def script_load(script)
        script = script.first if script.is_a?(Array)

        # Validate here rather than letting a non-String flatten into extra
        # SCRIPT LOAD wire arguments and fail as a server-side arity error.
        raise ArgumentError, "script must be a string" unless script.is_a?(String)
        raise ArgumentError, "script cannot be empty" if script.empty?

        call("SCRIPT", "LOAD", script)
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
      # @example Positional form, matching redis-rb's eval(script, keys, argv)
      #   valkey.eval("return KEYS[1] .. ARGV[1]", ["mykey"], ["myarg"])
      #     # => "mykeynyarg"
      # @example Integer key-count form, matching valkey-cli and the Valkey docs
      #   valkey.eval("return {KEYS[1], ARGV[1]}", 1, "mykey", "myarg")
      #     # => ["mykey", "myarg"]
      def eval(script, *rest, keys: nil, args: nil)
        # Validate script parameter
        raise ArgumentError, "script must be a string" unless script.is_a?(String)
        raise ArgumentError, "script cannot be empty" if script.empty?

        keys, args = split_keys_and_args(rest, keys, args)

        call("EVAL", script, keys.size, *keys, *args)
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
      # @example Positional form, matching redis-rb's evalsha(sha, keys, argv)
      #   valkey.evalsha(sha, ["user"], ["123"])
      #     # => "user:123"
      # @example Integer key-count form, matching valkey-cli and the Valkey docs
      #   valkey.evalsha(sha, 1, "user", "123")
      #     # => "user:123"
      def evalsha(sha, *rest, keys: nil, args: nil)
        # Validate SHA1 hash parameter
        raise ArgumentError, "sha1 hash must be a string" unless sha.is_a?(String)
        raise ArgumentError, "sha1 hash must be a 40-character hexadecimal string" unless valid_sha1?(sha)

        keys, args = split_keys_and_args(rest, keys, args)

        call("EVALSHA", sha, keys.size, *keys, *args)
      end

      # Execute a read-only Lua script on the server.
      #
      # This is a read-only variant of EVAL that cannot execute commands
      # that modify data. It can be routed to read replicas.
      #
      # @param [String] script the Lua script to execute
      # @param [Array<String>] keys array of key names that the script will access
      # @param [Array<Object>] args array of arguments to pass to the script
      # @return [Object] the result of the script execution
      #
      # @example Execute a read-only script
      #   valkey.eval_ro("return redis.call('get', KEYS[1])", keys: ["mykey"])
      #     # => "myvalue"
      # @example Integer key-count form
      #   valkey.eval_ro("return redis.call('get', KEYS[1])", 1, "mykey")
      #     # => "myvalue"
      #
      # @see https://valkey.io/commands/eval_ro/
      def eval_ro(script, *rest, keys: nil, args: nil)
        raise ArgumentError, "script must be a string" unless script.is_a?(String)
        raise ArgumentError, "script cannot be empty" if script.empty?

        keys, args = split_keys_and_args(rest, keys, args)

        call("EVAL_RO", script, keys.size, *keys, *args)
      end

      # Execute a cached read-only Lua script by its SHA1 hash.
      #
      # This is a read-only variant of EVALSHA that cannot execute commands
      # that modify data. It can be routed to read replicas.
      #
      # @param [String] sha the SHA1 hash of the script to execute
      # @param [Array<String>] keys array of key names that the script will access
      # @param [Array<Object>] args array of arguments to pass to the script
      # @return [Object] the result of the script execution
      #
      # @example Execute a cached read-only script
      #   sha = valkey.script_load("return redis.call('get', KEYS[1])")
      #   valkey.evalsha_ro(sha, keys: ["mykey"])
      #     # => "myvalue"
      # @example Integer key-count form
      #   valkey.evalsha_ro(sha, 1, "mykey")
      #     # => "myvalue"
      #
      # @see https://valkey.io/commands/evalsha_ro/
      def evalsha_ro(sha, *rest, keys: nil, args: nil)
        raise ArgumentError, "sha1 hash must be a string" unless sha.is_a?(String)
        raise ArgumentError, "sha1 hash must be a 40-character hexadecimal string" unless valid_sha1?(sha)

        keys, args = split_keys_and_args(rest, keys, args)

        call("EVALSHA_RO", sha, keys.size, *keys, *args)
      end

      # Execute a cached script via the glide-ffi `invoke_script` entry point.
      #
      # No longer used by eval/evalsha - they dispatch real wire commands now.
      # Retained as the FFI seam for the `Script` object proposed in #206, and
      # still exercised by the scripting tests. Note that its glide-core
      # NOSCRIPT self-heal relies on the client-side script container that
      # `script_load` no longer populates, so a SHA this client never stored
      # will surface a NOSCRIPT CommandError rather than being re-uploaded.
      # Emits no OpenTelemetry span (span_ptr is hardcoded to 0 below).
      def invoke_script(script, args: [], keys: [])
        # Must hold onto the returned buffers (_arg_bufs/_keys_bufs) for the
        # lifetime of this method - they back arg_ptrs/keys_ptrs, and letting
        # them go out of scope (e.g. by only capturing the first 2 return
        # values) makes them eligible for GC before the native call below
        # reads through those pointers, corrupting ARGV/KEYS with freed memory.
        arg_ptrs, arg_lens, _arg_bufs, flattened_args = build_command_args(args)
        keys_ptrs, keys_lens, _keys_bufs, flattened_keys = build_command_args(keys)

        route = ""
        route_buf = FFI::MemoryPointer.from_string(route)

        # Use from_string to ensure proper null termination
        sha = FFI::MemoryPointer.from_string(script)

        begin
          res = Bindings.invoke_script(
            @connection,
            0,
            sha,
            flattened_keys.size,
            keys_ptrs,
            keys_lens,
            flattened_args.size,
            arg_ptrs,
            arg_lens,
            route_buf,
            route.bytesize,
            0 # span_ptr for OpenTelemetry (0 = no span)
          )

          convert_response(res)
        ensure
          Bindings.free_command_result(res) if res && !res.null?
        end
      end

      private

      # Resolve the KEYS/ARGV split from the three call shapes the scripting
      # commands accept, and normalize both to Arrays of Strings.
      #
      # 1. Integer key-count form, as used by the Valkey docs and valkey-cli:
      #      eval(script, 1, "mykey", "myarg")
      # 2. redis-rb's two-array positional form:
      #      eval(script, ["mykey"], ["myarg"])
      # 3. Keyword form:
      #      eval(script, keys: ["mykey"], args: ["myarg"])
      #
      # Integer and Array are disjoint in the first positional slot, so
      # recognizing the integer form is a strict superset - it cannot change
      # the meaning of any call that already worked. Anything the caller
      # plainly meant as a key count but that isn't an Integer, and any extra
      # positional beyond (keys, argv), raises instead of being reinterpreted:
      # silently proceeding with a different meaning is the defect this fixes.
      #
      # @return [Array(Array<String>, Array<String>)] the keys and args
      def split_keys_and_args(rest, keys, args)
        if rest.first.is_a?(Integer)
          if keys || args
            raise ArgumentError,
                  "cannot mix the integer key-count form with the keys:/args: keywords"
          end

          numkeys, *positional = rest

          raise ArgumentError, "numkeys must be non-negative" if numkeys.negative?

          if numkeys > positional.size
            raise ArgumentError,
                  "numkeys (#{numkeys}) exceeds the number of arguments given (#{positional.size})"
          end

          # shift consumes the keys; whatever remains is ARGV
          keys = positional.shift(numkeys)
          args = positional
        else
          if rest.first.is_a?(Numeric)
            raise ArgumentError,
                  "numkeys must be an Integer, got #{rest.first.class} (#{rest.first.inspect})"
          end

          if rest.size > 2
            raise ArgumentError,
                  "wrong number of positional arguments (given #{rest.size}, expected at most 2: keys, argv). " \
                  "To pass a key count, make it an Integer: eval(script, #{rest.size - 1}, ...)"
          end

          keys ||= rest[0] || []
          args ||= rest[1] || []
        end

        # Stringify before handing off to #call, whose flattening raises
        # TypeError on non-String/Symbol/Integer/Float leaves. Converting here
        # preserves the lenient #to_s coercion these commands have always had.
        begin
          [Array(keys).map(&:to_s), Array(args).map(&:to_s)]
        rescue StandardError => e
          raise ArgumentError, "failed to convert keys or args to strings: #{e.message}"
        end
      end

      # Validate SHA1 hash format (40-character hexadecimal string)
      def valid_sha1?(sha)
        sha.is_a?(String) && sha.length == 40 && sha.match?(/\A[a-fA-F0-9]{40}\z/)
      end
    end
  end
end
