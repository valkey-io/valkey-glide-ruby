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

      # ACL Commands - Access Control List management

      # List the ACL categories or the commands inside a category.
      #
      # @example List all categories
      #   valkey.acl_cat
      #     # => ["keyspace", "read", "write", ...]
      # @example List commands in a category
      #   valkey.acl_cat("dangerous")
      #     # => ["flushdb", "flushall", ...]
      #
      # @param [String] category optional category name to list commands
      # @return [Array<String>] array of categories or commands
      #
      # @see https://valkey.io/commands/acl-cat/
      def acl_cat(category = nil)
        args = category ? [category] : []
        send_command(RequestType::ACL_CAT, args)
      end

      # Remove the specified ACL users.
      #
      # @example Delete a user
      #   valkey.acl_deluser("alice")
      #     # => 1
      # @example Delete multiple users
      #   valkey.acl_deluser("alice", "bob")
      #     # => 2
      #
      # @param [Array<String>] usernames one or more usernames to delete
      # @return [Integer] number of users deleted
      #
      # @see https://valkey.io/commands/acl-deluser/
      def acl_deluser(*usernames)
        send_command(RequestType::ACL_DEL_USER, usernames)
      end

      # Simulate the execution of a command by a user without actually running it.
      #
      # @example Test if user can run a command
      #   valkey.acl_dryrun("alice", "get", "key1")
      #     # => "OK"
      # @example Test a command that would be denied
      #   valkey.acl_dryrun("alice", "set", "key1", "value")
      #     # => "This user has no permissions to run the 'set' command"
      #
      # @param [String] username the username to test
      # @param [String] command the command to test
      # @param [Array<String>] args command arguments
      # @return [String] "OK" if allowed, or error message if denied
      #
      # @see https://valkey.io/commands/acl-dryrun/
      def acl_dryrun(username, command, *args)
        command_args = [username, command] + args
        send_command(RequestType::ACL_DRY_RUN, command_args)
      end

      # Generate a random password.
      #
      # @example Generate a password with default length
      #   valkey.acl_genpass
      #     # => "dd721260bfe1b3d9601e7fbab36de6d04e2e67b0ef1c53de59d45950db0dd3cc"
      # @example Generate a password with specific bit length
      #   valkey.acl_genpass(32)
      #     # => "355ef3dd"
      #
      # @param [Integer] bits optional number of bits (default: 256)
      # @return [String] the generated password
      #
      # @see https://valkey.io/commands/acl-genpass/
      def acl_genpass(bits = nil)
        args = bits ? [bits] : []
        send_command(RequestType::ACL_GEN_PASS, args)
      end

      # Get the rules for a specific ACL user.
      #
      # @example Get user rules
      #   valkey.acl_getuser("alice")
      #     # => ["flags" => ["on", "allkeys"], "passwords" => [...], ...]
      #
      # @param [String] username the username to query
      # @return [Array, nil] array of user properties, or nil if user doesn't exist
      #
      # @see https://valkey.io/commands/acl-getuser/
      def acl_getuser(username)
        send_command(RequestType::ACL_GET_USER, [username])
      end

      # List the current ACL rules in ACL config file format.
      #
      # @example List all ACL rules
      #   valkey.acl_list
      #     # => ["user default on nopass ~* &* +@all", "user alice on ..."]
      #
      # @return [Array<String>] array of ACL rules
      #
      # @see https://valkey.io/commands/acl-list/
      def acl_list
        send_command(RequestType::ACL_LIST)
      end

      # Reload the ACL rules from the configured ACL file.
      #
      # @example Reload ACL from file
      #   valkey.acl_load
      #     # => "OK"
      #
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/acl-load/
      def acl_load
        send_command(RequestType::ACL_LOAD)
      end

      # List latest ACL security events.
      #
      # @example Get recent ACL log entries
      #   valkey.acl_log
      #     # => [{"count" => 1, "reason" => "auth", ...}, ...]
      # @example Get specific number of log entries
      #   valkey.acl_log(10)
      #     # => [...]
      # @example Reset the ACL log
      #   valkey.acl_log("RESET")
      #     # => "OK"
      #
      # @param [Integer, String] count_or_reset number of entries or "RESET" to clear the log
      # @return [Array<Hash>, String] array of log entries, or "OK" if reset
      #
      # @see https://valkey.io/commands/acl-log/
      def acl_log(count_or_reset = nil)
        args = count_or_reset ? [count_or_reset] : []
        send_command(RequestType::ACL_LOG, args)
      end

      # Save the current ACL rules to the configured ACL file.
      #
      # @example Save ACL to file
      #   valkey.acl_save
      #     # => "OK"
      #
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/acl-save/
      def acl_save
        send_command(RequestType::ACL_SAVE)
      end

      # Modify or create ACL rules for a user.
      #
      # @example Create a user with password
      #   valkey.acl_setuser("alice", "on", ">password", "~*", "+@all")
      #     # => "OK"
      # @example Create a read-only user
      #   valkey.acl_setuser("bob", "on", ">pass123", "~*", "+@read")
      #     # => "OK"
      # @example Disable a user
      #   valkey.acl_setuser("alice", "off")
      #     # => "OK"
      #
      # @param [String] username the username to modify or create
      # @param [Array<String>] rules ACL rules to apply
      # @return [String] "OK"
      #
      # @see https://valkey.io/commands/acl-setuser/
      def acl_setuser(username, *rules)
        command_args = [username] + rules
        send_command(RequestType::ACL_SET_USER, command_args)
      end

      # List all configured ACL users.
      #
      # @example List all users
      #   valkey.acl_users
      #     # => ["default", "alice", "bob"]
      #
      # @return [Array<String>] array of usernames
      #
      # @see https://valkey.io/commands/acl-users/
      def acl_users
        send_command(RequestType::ACL_USERS)
      end

      # Return the username of the current connection.
      #
      # @example Get current username
      #   valkey.acl_whoami
      #     # => "default"
      #
      # @return [String] the current username
      #
      # @see https://valkey.io/commands/acl-whoami/
      def acl_whoami
        send_command(RequestType::ACL_WHOAMI)
      end

      # Control ACL configuration (convenience method).
      #
      # @example List all categories
      #   valkey.acl(:cat)
      #     # => ["keyspace", "read", ...]
      # @example Delete a user
      #   valkey.acl(:deluser, "alice")
      #     # => 1
      # @example Test command execution
      #   valkey.acl(:dryrun, "alice", "get", "key1")
      #     # => "OK"
      # @example Generate a password
      #   valkey.acl(:genpass)
      #     # => "dd721260..."
      # @example Get user info
      #   valkey.acl(:getuser, "alice")
      #     # => [...]
      # @example List all ACL rules
      #   valkey.acl(:list)
      #     # => ["user default on ...", ...]
      # @example Reload ACL from file
      #   valkey.acl(:load)
      #     # => "OK"
      # @example Get ACL log
      #   valkey.acl(:log)
      #     # => [...]
      # @example Save ACL to file
      #   valkey.acl(:save)
      #     # => "OK"
      # @example Set user rules
      #   valkey.acl(:setuser, "alice", "on", ">password")
      #     # => "OK"
      # @example List all users
      #   valkey.acl(:users)
      #     # => ["default", "alice"]
      # @example Get current username
      #   valkey.acl(:whoami)
      #     # => "default"
      #
      # @param [String, Symbol] subcommand the subcommand
      #   (cat, deluser, dryrun, genpass, getuser, list, load, log, save, setuser, users, whoami)
      # @param [Array] args arguments for the subcommand
      # @return [Object] depends on subcommand
      def acl(subcommand, *args)
        subcommand = subcommand.to_s.downcase
        send("acl_#{subcommand}", *args)
      end

      # Return a human-readable latency analysis report.
      #
      # @return [String] human-readable latency analysis
      #
      # @example
      #   valkey.latency_doctor
      #     # => "Dave, I observed latency events in this Redis instance..."
      #
      # @see https://valkey.io/commands/latency-doctor/
      def latency_doctor
        send_command(RequestType::LATENCY_DOCTOR)
      end

      # Return an ASCII-art graph of the latency samples for the specified event.
      #
      # @param [String] event the event name to graph
      # @return [String] ASCII-art graph of latency samples
      #
      # @example
      #   valkey.latency_graph("command")
      #     # => "command - high 500 ms, low 501 ms (all time high 500 ms)\n..."
      #
      # @see https://valkey.io/commands/latency-graph/
      def latency_graph(event)
        send_command(RequestType::LATENCY_GRAPH, [event])
      end

      # Return a latency histogram for the specified commands.
      #
      # @param [Array<String>] commands optional command names to get histograms for
      # @return [Array] array of latency histogram entries
      #
      # @example Get histogram for all commands
      #   valkey.latency_histogram
      #     # => [["SET", [["0-1", 100], ["2-3", 50], ...]], ...]
      # @example Get histogram for specific commands
      #   valkey.latency_histogram("SET", "GET")
      #     # => [["SET", [["0-1", 100], ...]], ["GET", [["0-1", 200], ...]]]
      #
      # @see https://valkey.io/commands/latency-histogram/
      def latency_histogram(*commands)
        args = commands.empty? ? [] : commands
        send_command(RequestType::LATENCY_HISTOGRAM, args)
      end

      # Return the latency time series for the specified event.
      #
      # @param [String] event the event name to get history for
      # @return [Array] array of [timestamp, latency] pairs
      #
      # @example
      #   valkey.latency_history("command")
      #     # => [[1234567890, 100], [1234567891, 150], ...]
      #
      # @see https://valkey.io/commands/latency-history/
      def latency_history(event)
        send_command(RequestType::LATENCY_HISTORY, [event])
      end

      # Return the latest latency samples for all events.
      #
      # @return [Array] array of event information arrays
      #   Each entry is [event_name, timestamp, latest_latency, max_latency]
      #
      # @example
      #   valkey.latency_latest
      #     # => [["command", 1234567890, 100, 200], ["fast-command", 1234567891, 50, 100]]
      #
      # @see https://valkey.io/commands/latency-latest/
      def latency_latest
        send_command(RequestType::LATENCY_LATEST)
      end

      # Reset latency data for all events or specific events.
      #
      # @param [Array<String>] events optional event names to reset
      #   If no events are specified, resets all latency data
      # @return [Integer] number of events reset
      #
      # @example Reset all latency data
      #   valkey.latency_reset
      #     # => 3
      # @example Reset specific events
      #   valkey.latency_reset("command", "fast-command")
      #     # => 2
      #
      # @see https://valkey.io/commands/latency-reset/
      def latency_reset(*events)
        args = events.empty? ? [] : events
        send_command(RequestType::LATENCY_RESET, args)
      end

      # Return a human-readable memory problems report.
      #
      # @return [String] human-readable memory analysis report
      #
      # @example
      #   valkey.memory_doctor
      #     # => "Hi Sam, this is the Valkey memory doctor..."
      #
      # @see https://valkey.io/commands/memory-doctor/
      def memory_doctor
        send_command(RequestType::MEMORY_DOCTOR)
      end

      # Return memory allocator statistics.
      #
      # @return [String] memory allocator statistics
      #
      # @example
      #   valkey.memory_malloc_stats
      #     # => "___ Begin jemalloc statistics ___..."
      #
      # @see https://valkey.io/commands/memory-malloc-stats/
      def memory_malloc_stats
        send_command(RequestType::MEMORY_MALLOC_STATS)
      end

      # Ask the allocator to release memory back to the operating system.
      #
      # @return [String] "OK"
      #
      # @example
      #   valkey.memory_purge
      #     # => "OK"
      #
      # @see https://valkey.io/commands/memory-purge/
      def memory_purge
        send_command(RequestType::MEMORY_PURGE)
      end

      # Return memory usage statistics.
      #
      # @return [Hash] memory usage statistics
      #
      # @example
      #   valkey.memory_stats
      #     # => {"peak.allocated" => "1048576", "total.allocated" => "524288", ...}
      #
      # @see https://valkey.io/commands/memory-stats/
      def memory_stats
        send_command(RequestType::MEMORY_STATS) do |reply|
          if reply.is_a?(Array)
            Hash[*reply]
          else
            reply
          end
        end
      end

      # Return the memory usage in bytes of a key and its value.
      #
      # @param [String] key the key to check
      # @param [Hash] options optional parameters
      #   - `:samples => Integer`: number of samples for nested data structures (default: 5)
      # @return [Integer, nil] memory usage in bytes, or nil if key doesn't exist
      #
      # @example Get memory usage for a key
      #   valkey.memory_usage("mykey")
      #     # => 1024
      # @example Get memory usage with custom samples
      #   valkey.memory_usage("mykey", samples: 10)
      #     # => 2048
      #
      # @see https://valkey.io/commands/memory-usage/
      def memory_usage(key, samples: nil)
        args = [key]
        args << "SAMPLES" << samples.to_s if samples
        send_command(RequestType::MEMORY_USAGE, args)
      end

      # Send a generic COMMAND subcommand.
      #
      # @param [Symbol, String] subcommand The COMMAND subcommand to run, e.g. :count, :docs, :info, :list
      # @param [Array] args Arguments for the subcommand
      # @return [Object] Depends on subcommand
      # @example
      #   command(:count)                    # => 234
      #   command(:list)                     # => ["GET", "SET", ...]
      #   command(:info, "GET", "SET")       # => [[...], [...]]
      def command(subcommand, *args)
        send("command_#{subcommand.to_s.downcase}", *args)
      end

      # Return details about every Redis command.
      #
      # @return [Array] array of command information arrays
      #
      # @example
      #   valkey.command
      #     # => [["GET", 2, ["readonly", "fast"], 1, 1, 1], ...]
      #
      # @see https://valkey.io/commands/command/
      def command_
        send_command(RequestType::COMMAND_)
      end

      # Return the total number of commands in the server.
      #
      # @return [Integer] total number of commands
      #
      # @example
      #   valkey.command_count
      #     # => 234
      #
      # @see https://valkey.io/commands/command-count/
      def command_count
        send_command(RequestType::COMMAND_COUNT)
      end

      # Return documentary information about one or more commands.
      #
      # @param [Array<String>] commands command names to get documentation for
      # @return [Array] array of command documentation hashes
      #
      # @example Get docs for specific commands
      #   valkey.command_docs("GET", "SET")
      #     # => [{"summary" => "...", "since" => "1.0.0", ...}, ...]
      # @example Get docs for all commands
      #   valkey.command_docs
      #     # => [{"summary" => "...", ...}, ...]
      #
      # @see https://valkey.io/commands/command-docs/
      def command_docs(*commands)
        args = commands.empty? ? [] : commands
        send_command(RequestType::COMMAND_DOCS, args) do |reply|
          if reply.is_a?(Array)
            # Convert array of arrays to array of hashes
            reply.map do |cmd_doc|
              if cmd_doc.is_a?(Array)
                Hash[*cmd_doc]
              else
                cmd_doc
              end
            end
          else
            reply
          end
        end
      end

      # Extract keys from a full Redis command.
      #
      # @param [String, Array<String>] command the command and its arguments
      # @return [Array] array of key positions
      #
      # @example
      #   valkey.command_get_keys("GET", "mykey")
      #     # => [0]
      #   valkey.command_get_keys("MSET", "key1", "val1", "key2", "val2")
      #     # => [0, 2]
      #
      # @see https://valkey.io/commands/command-getkeys/
      def command_get_keys(*command)
        send_command(RequestType::COMMAND_GET_KEYS, command)
      end

      # Extract keys and their flags from a full Redis command.
      #
      # @param [String, Array<String>] command the command and its arguments
      # @return [Array] array of [key_position, flags] pairs
      #
      # @example
      #   valkey.command_get_keys_and_flags("GET", "mykey")
      #     # => [[0, ["RW", "access"]], ...]
      #
      # @see https://valkey.io/commands/command-getkeysandflags/
      def command_get_keys_and_flags(*command)
        send_command(RequestType::COMMAND_GET_KEYS_AND_FLAGS, command)
      end

      # Return information about one or more commands.
      #
      # @param [Array<String>] commands command names to get information for
      # @return [Array] array of command information arrays
      #
      # @example Get info for specific commands
      #   valkey.command_info("GET", "SET")
      #     # => [[...], [...]]
      # @example Get info for all commands
      #   valkey.command_info
      #     # => [[...], ...]
      #
      # @see https://valkey.io/commands/command-info/
      def command_info(*commands)
        args = commands.empty? ? [] : commands
        send_command(RequestType::COMMAND_INFO, args)
      end

      # Return an array of command names.
      #
      # @param [Hash] options optional filters
      #   - `:filterby => String`: filter by module name (e.g., "json")
      #   - `:aclcat => String`: filter by ACL category
      #   - `:pattern => String`: pattern to match (used with filterby)
      # @return [Array<String>] array of command names
      #
      # @example Get all commands
      #   valkey.command_list
      #     # => ["GET", "SET", "DEL", ...]
      # @example Filter by module with pattern
      #   valkey.command_list(filterby: "json", pattern: "json.*")
      #     # => ["json.get", "json.set", ...]
      # @example Filter by ACL category
      #   valkey.command_list(aclcat: "read")
      #     # => ["GET", "MGET", ...]
      #
      # @see https://valkey.io/commands/command-list/
      def command_list(filterby: nil, aclcat: nil, pattern: nil)
        args = []
        if aclcat
          args << "FILTERBY" << "ACLCAT" << aclcat
        elsif filterby && pattern
          args << "FILTERBY" << filterby << pattern
        end
        send_command(RequestType::COMMAND_LIST, args)
      end
    end
  end
end
