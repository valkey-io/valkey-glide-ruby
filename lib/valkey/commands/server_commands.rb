# frozen_string_literal: true

class Valkey
  module Commands
    # this module contains commands related to server management.
    #
    # @see https://valkey.io/commands/#server
    #
    module ServerCommands
      # Asynchronously rewrite the append-only file.
      #
      # @return [String] `OK`
      def bgrewriteaof
        send_command(RequestType::BG_REWRITE_AOF)
      end

      # Asynchronously save the dataset to disk.
      #
      # @return [String] `OK`
      def bgsave
        send_command(RequestType::BG_SAVE)
      end

      # Get or set server configuration parameters.
      #
      # @param [Symbol] action e.g. `:get`, `:set`, `:resetstat`
      # @return [String, Hash] string reply, or hash when retrieving more than one
      #   property with `CONFIG GET`
      def config(action, *args)
        send("config_#{action.to_s.downcase}", *args)
      end

      # Get server configuration parameters.
      #
      # Sends the CONFIG GET command with the given arguments.
      #
      # @param [Array<String>] args Configuration parameters to get
      # @return [Hash, String] Returns a Hash if multiple parameters are requested,
      #   otherwise returns a String with the value.
      #
      # @example Get all configuration parameters
      #   config_get('*')
      #
      # @example Get a specific parameter
      #   config_get('maxmemory')
      #
      # @note Returns a Hash with parameter names as keys and values as values when multiple params requested.
      def config_get(*args)
        send_command(RequestType::CONFIG_GET, args) do |reply|
          if reply.is_a?(Array)
            Hash[*reply]
          else
            reply
          end
        end
      end

      # Set server configuration parameters.
      #
      # Sends the CONFIG SET command with the given key-value pairs.
      #
      # @param [Array<String>] args Key-value pairs to set configuration
      # @return [String] Returns "OK" if successful
      #
      # @example Set maxmemory to 100mb
      #   config_set('maxmemory', '100mb')
      def config_set(*args)
        send_command(RequestType::CONFIG_SET, args)
      end

      # Reset the server's statistics.
      #
      # Sends the CONFIG RESETSTAT command.
      #
      # @return [String] Returns "OK" if successful
      #
      # @example
      #   config_resetstat
      def config_resetstat
        send_command(RequestType::CONFIG_RESET_STAT)
      end

      # Rewrite the server configuration file.
      #
      # Sends the CONFIG REWRITE command.
      #
      # @return [String] Returns "OK" if successful
      #
      # @example
      #   config_rewrite
      def config_rewrite
        send_command(RequestType::CONFIG_REWRITE)
      end

      # Send a generic CLIENT subcommand.
      #
      # @param [Symbol, String] subcommand The CLIENT subcommand to run, e.g. :list, :id, :kill, etc.
      # @param [Array] args Arguments for the subcommand
      # @return [Object] Depends on subcommand
      def client(subcommand, *args)
        send("client_#{subcommand.to_s.downcase}", *args)
      end

      # Get a list of client connections.
      #
      # @return [Array<Hash>] List of clients, each represented as a Hash of attributes
      # @example
      #   clients = client_list
      #   clients.each { |client| puts client["id"] }
      def client_list
        send_command(RequestType::CLIENT_LIST) do |reply|
          reply.lines.map do |line|
            entries = line.chomp.split(/[ =]/)
            Hash[entries.each_slice(2).to_a]
          end
        end
      end

      # Get the name of the current connection.
      #
      # @return [String, nil] Client name or nil if not set
      # @example
      #   name = client_get_name
      def client_get_name
        send_command(RequestType::CLIENT_GET_NAME)
      end

      # Set the name of the current connection.
      #
      # @param [String] name New name for the client connection
      # @return [String] "OK" if successful
      # @example
      #   client_set_name("my_client")
      def client_set_name(*args)
        send_command(RequestType::CLIENT_SET_NAME, args)
      end

      # Kill client connections by address or ID.
      #
      # @param [Array<String>] args Kill filters such as "addr", "id", etc.
      # @return [Integer] Number of clients killed
      # @example
      #   client_kill("addr", "127.0.0.1:6379")
      def client_kill(*args)
        send_command(RequestType::CLIENT_KILL, args)
      end

      # Simplified client kill command, similar to `client_kill`.
      #
      # @param [Array<String>] args Kill filters
      # @return [Integer] Number of clients killed
      def client_kill_simple(*args)
        send_command(RequestType::CLIENT_KILL, args)
      end

      # Get the current connection’s client ID.
      #
      # @return [Integer] Client ID
      # @example
      #   id = client_id
      def client_id
        send_command(RequestType::CLIENT_ID)
      end

      # Unblock a client by client ID.
      #
      # @param [Integer] client_id ID of the client to unblock
      # @return [Integer] 1 if unblocked, 0 if no client was blocked
      # @example
      #   client_unblock(42)
      def client_unblock(*args)
        send_command(RequestType::CLIENT_UNBLOCK, args)
      end

      # Pause processing of commands from clients for a given time.
      #
      # @param [Integer] timeout Time in milliseconds to pause clients
      # @param [Symbol] mode Pause mode, e.g., `:all` to pause all clients or `:write` to pause writes only
      # @return [String] "OK"
      # @example
      #   client_pause(1000, :all)
      def client_pause(*args)
        send_command(RequestType::CLIENT_PAUSE, args)
      end

      # Resume processing of commands from clients after a pause.
      #
      # @return [String] "OK"
      # @example
      #   client_unpause
      def client_unpause
        send_command(RequestType::CLIENT_UNPAUSE)
      end

      # Enable or disable client tracking.
      #
      # @param [Array] args Tracking subcommand arguments
      # @return [String] Server response
      def client_tracking(*args)
        send_command(RequestType::CLIENT_TRACKING, args)
      end

      # Get information about client tracking.
      #
      # @return [Array] Tracking info
      def client_tracking_info
        send_command(RequestType::CLIENT_TRACKING_INFO)
      end

      # Control client reply behavior (e.g., ON, OFF, SKIP).
      #
      # @param [Array] args Reply mode arguments
      # @return [String] Server response
      def client_reply(*args)
        send_command(RequestType::CLIENT_REPLY, args)
      end

      # Get information about the current client connection.
      #
      # @return [String] Client info key-value pairs
      def client_info
        send_command(RequestType::CLIENT_INFO)
      end

      # Set client information fields.
      #
      # @param [Array] args Key-value pairs to set client info fields
      # @return [String] Server response
      def client_set_info(*args)
        send_command(RequestType::CLIENT_SET_INFO, args)
      end

      # Enable or disable client query caching.
      #
      # @param [Array] args Caching subcommand arguments
      # @return [String] Server response
      def client_caching(*args)
        send_command(RequestType::CLIENT_CACHING, args)
      end

      # Get the client ID that the current client is redirected to.
      #
      # @return [Integer] Client ID, or 0 if not redirected
      def client_getredir
        send_command(RequestType::CLIENT_GET_REDIR)
      end

      # Enable or disable the no-eviction flag for the current client.
      #
      # @param [Symbol, String] mode :on or :off
      # @return [String] Server response
      def client_no_evict(*args)
        send_command(RequestType::CLIENT_NO_EVICT, args)
      end

      # Enable or disable the no-touch flag for the current client.
      #
      # @param [Symbol, String] mode :on or :off
      # @return [String] Server response
      def client_no_touch(*args)
        send_command(RequestType::CLIENT_NO_TOUCH, args)
      end

      # Return the number of keys in the selected database.
      #
      # @return [Integer]
      def dbsize
        send_command(RequestType::DB_SIZE)
      end

      # Remove all keys from all databases.
      #
      # @param [Hash] options
      #   - `:async => Boolean`: async flush (default: false)
      # @return [String] `OK`
      def flushall(options = nil)
        if options && options[:async]
          send_command(RequestType::FLUSH_ALL, ["async"])
        else
          send_command(RequestType::FLUSH_ALL)
        end
      end

      # Remove all keys from the current database.
      #
      # @param [Hash] options
      #   - `:async => Boolean`: async flush (default: false)
      # @return [String] `OK`
      def flushdb(options = nil)
        if options && options[:async]
          send_command(RequestType::FLUSH_DB, ["async"])
        else
          send_command(RequestType::FLUSH_DB)
        end
      end

      # Get information and statistics about the server.
      #
      # @param [String, Symbol] cmd e.g. "commandstats"
      # @return [Hash<String, String>]
      def info(cmd = nil)
        send_command(RequestType::INFO, [cmd].compact) do |reply|
          if reply.is_a?(String)
            reply = Utils::HashifyInfo.call(reply)

            if cmd && cmd.to_s == "commandstats"
              # Extract nested hashes for INFO COMMANDSTATS
              reply = Hash[reply.map do |k, v|
                v = v.split(",").map { |e| e.split("=") }
                [k[/^cmdstat_(.*)$/, 1], Hash[v]]
              end]
            end
          end

          reply
        end
      end

      # Get the UNIX time stamp of the last successful save to disk.
      #
      # @return [Integer]
      def lastsave
        send_command(RequestType::LAST_SAVE)
      end

      # Listen for all requests received by the server in real time.
      #
      # There is no way to interrupt this command.
      #
      # @yield a block to be called for every line of output
      # @yieldparam [String] line timestamp and command that was executed
      def monitor
        synchronize do |client|
          client = client.pubsub
          client.call_v([:monitor])
          loop do
            yield client.next_event
          end
        end
      end

      # Synchronously save the dataset to disk.
      #
      # @return [String]
      def save
        send_command(RequestType::SAVE)
      end

      # Synchronously save the dataset to disk and then shut down the server.
      def shutdown
        synchronize do |client|
          client.disable_reconnection do
            client.call_v([:shutdown])
          rescue ConnectionError
            # This means Redis has probably exited.
            nil
          end
        end
      end

      # Make the server a slave of another instance, or promote it as master.
      def slaveof(host, port)
        send_command(RequestType::SLAVE_OF, [host, port])
      end

      # Interact with the slowlog (get, len, reset)
      #
      # @param [String] subcommand e.g. `get`, `len`, `reset`
      # @param [Integer] length maximum number of entries to return
      # @return [Array<String>, Integer, String] depends on subcommand
      def slowlog(subcommand, length = nil)
        args = [:slowlog, subcommand]
        args << Integer(length) if length
        send_command(args)
      end

      # Internal command used for replication.
      def sync
        send_command(RequestType::SYNC)
      end

      # Return the server time.
      #
      # @example
      #   r.time # => [ 1333093196, 606806 ]
      #
      # @return [Array<Integer>] tuple of seconds since UNIX epoch and
      #   microseconds in the current second
      def time
        send_command(RequestType::TIME)
      end

      # RequestType::DEBUG not exist
      def debug(*args)
        send_command(RequestType::DEBUG, args)
      end
    end
  end
end
