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
    end
  end
end
