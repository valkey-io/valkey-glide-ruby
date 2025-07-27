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

      # TODO: not implemented in Glide
      def eval(script, args: [], keys: []); end

      # TODO: not implemented in Glide
      def evalsha(script, args: [], keys: []); end

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
    end
  end
end
