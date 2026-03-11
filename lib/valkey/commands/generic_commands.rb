# frozen_string_literal: true

class Valkey
  module Commands
    # this module contains generic commands that are not specific to any data type
    #
    # @see https://valkey.io/commands/#generic
    #
    module GenericCommands
      # Scan the keyspace
      #
      # @example Retrieve the first batch of keys
      #   valkey.scan(0)
      #     # => ["4", ["key:21", "key:47", "key:42"]]
      # @example Retrieve a batch of keys matching a pattern
      #   valkey.scan(4, :match => "key:1?")
      #     # => ["92", ["key:13", "key:18"]]
      # @example Retrieve a batch of keys of a certain type
      #   valkey.scan(92, :type => "zset")
      #     # => ["173", ["sortedset:14", "sortedset:78"]]
      #
      # @param [String, Integer] cursor the cursor of the iteration
      # @param [Hash] options
      #   - `:match => String`: only return keys matching the pattern
      #   - `:count => Integer`: return count keys at most per iteration
      #   - `:type => String`: return keys only of the given type
      #
      # @return [String, Array<String>] the next cursor and all found keys
      #
      def scan(cursor, **options)
        _scan(RequestType::SCAN, cursor, [], **options)
      end

      # Scan the keyspace
      #
      # @example Retrieve all of the keys (with possible duplicates)
      #   valkey.scan_each.to_a
      #     # => ["key:21", "key:47", "key:42"]
      # @example Execute block for each key matching a pattern
      #   valkey.scan_each(:match => "key:1?") {|key| puts key}
      #     # => key:13
      #     # => key:18
      # @example Execute block for each key of a type
      #   valkey.scan_each(:type => "hash") {|key| puts valkey.type(key)}
      #     # => "hash"
      #     # => "hash"
      #
      # @param [Hash] options
      #   - `:match => String`: only return keys matching the pattern
      #   - `:count => Integer`: return count keys at most per iteration
      #   - `:type => String`: return keys only of the given type
      #
      # @return [Enumerator] an enumerator for all found keys
      #
      # def scan_each(**options, &block)
      #   return to_enum(:scan_each, **options) unless block_given?
      #
      #   cursor = 0
      #   loop do
      #     cursor, keys = scan(cursor, **options)
      #     keys.each(&block)
      #     break if cursor == "0"
      #   end
      # end

      # Remove the expiration from a key.
      #
      # @param [String] key
      # @return [Boolean] whether the timeout was removed or not
      def persist(key)
        send_command(RequestType::PERSIST, [key])
      end

      # Set a key's time to live in seconds.
      #
      # @param [String] key
      # @param [Integer] seconds time to live
      # @param [Hash] options
      #   - `:nx => true`: Set expiry only when the key has no expiry.
      #   - `:xx => true`: Set expiry only when the key has an existing expiry.
      #   - `:gt => true`: Set expiry only when the new expiry is greater than current one.
      #   - `:lt => true`: Set expiry only when the new expiry is less than current one.
      # @return [Boolean] whether the timeout was set or not
      def expire(key, seconds, nx: nil, xx: nil, gt: nil, lt: nil)
        args = [key, Integer(seconds)]
        args << "NX" if nx
        args << "XX" if xx
        args << "GT" if gt
        args << "LT" if lt

        send_command(RequestType::EXPIRE, args)
      end

      # Set the expiration for a key as a UNIX timestamp.
      #
      # @param [String] key
      # @param [Integer] unix_time expiry time specified as a UNIX timestamp
      # @param [Hash] options
      #   - `:nx => true`: Set expiry only when the key has no expiry.
      #   - `:xx => true`: Set expiry only when the key has an existing expiry.
      #   - `:gt => true`: Set expiry only when the new expiry is greater than current one.
      #   - `:lt => true`: Set expiry only when the new expiry is less than current one.
      # @return [Boolean] whether the timeout was set or not
      def expireat(key, unix_time, nx: nil, xx: nil, gt: nil, lt: nil)
        args = [key, Integer(unix_time)]
        args << "NX" if nx
        args << "XX" if xx
        args << "GT" if gt
        args << "LT" if lt

        send_command(RequestType::EXPIRE_AT, args)
      end

      # Get a key's expiry time specified as number of seconds from UNIX Epoch
      #
      # @param  [String] key
      # @return [Integer] expiry time specified as number of seconds from UNIX Epoch
      def expiretime(key)
        send_command(RequestType::EXPIRE_TIME, [key])
      end

      # Get the time to live (in seconds) for a key.
      #
      # @param [String] key
      # @return [Integer] remaining time to live in seconds.
      #
      # In valkey 2.6 or older the command returns -1 if the key does not exist or if
      # the key exist but has no associated expire.
      #
      # Starting with valkey 2.8 the return value in case of error changed:
      #
      #     - The command returns -2 if the key does not exist.
      #     - The command returns -1 if the key exists but has no associated expire.
      def ttl(key)
        send_command(RequestType::TTL, [key])
      end

      # Set a key's time to live in milliseconds.
      #
      # @param [String] key
      # @param [Integer] milliseconds time to live
      # @param [Hash] options
      #   - `:nx => true`: Set expiry only when the key has no expiry.
      #   - `:xx => true`: Set expiry only when the key has an existing expiry.
      #   - `:gt => true`: Set expiry only when the new expiry is greater than current one.
      #   - `:lt => true`: Set expiry only when the new expiry is less than current one.
      # @return [Boolean] whether the timeout was set or not
      def pexpire(key, milliseconds, nx: nil, xx: nil, gt: nil, lt: nil)
        args = [key, Integer(milliseconds)]
        args << "NX" if nx
        args << "XX" if xx
        args << "GT" if gt
        args << "LT" if lt

        send_command(RequestType::PEXPIRE, args)
      end

      # Set the expiration for a key as number of milliseconds from UNIX Epoch.
      #
      # @param [String] key
      # @param [Integer] ms_unix_time expiry time specified as number of milliseconds from UNIX Epoch.
      # @param [Hash] options
      #   - `:nx => true`: Set expiry only when the key has no expiry.
      #   - `:xx => true`: Set expiry only when the key has an existing expiry.
      #   - `:gt => true`: Set expiry only when the new expiry is greater than current one.
      #   - `:lt => true`: Set expiry only when the new expiry is less than current one.
      # @return [Boolean] whether the timeout was set or not
      def pexpireat(key, ms_unix_time, nx: nil, xx: nil, gt: nil, lt: nil)
        args = [key, Integer(ms_unix_time)]
        args << "NX" if nx
        args << "XX" if xx
        args << "GT" if gt
        args << "LT" if lt

        send_command(RequestType::PEXPIRE_AT, args)
      end

      # Get a key's expiry time specified as number of milliseconds from UNIX Epoch
      #
      # @param  [String] key
      # @return [Integer] expiry time specified as number of milliseconds from UNIX Epoch
      def pexpiretime(key)
        send_command(RequestType::PEXPIRE_TIME, [key])
      end

      # Get the time to live (in milliseconds) for a key.
      #
      # @param [String] key
      # @return [Integer] remaining time to live in milliseconds
      # In valkey 2.6 or older the command returns -1 if the key does not exist or if
      # the key exist but has no associated expire.
      #
      # Starting with valkey 2.8 the return value in case of error changed:
      #
      #     - The command returns -2 if the key does not exist.
      #     - The command returns -1 if the key exists but has no associated expire.
      def pttl(key)
        send_command(RequestType::PTTL, [key])
      end

      # Return a serialized version of the value stored at a key.
      #
      # @param [String] key
      # @return [String] serialized_value
      def dump(key)
        send_command(RequestType::DUMP, [key])
      end

      # Create a key using the serialized value, previously obtained using DUMP.
      #
      # @param [String] key
      # @param [String] ttl
      # @param [String] serialized_value
      # @param [Hash] options
      #   - `:replace => Boolean`: if false, raises an error if key already exists
      # @raise [valkey::CommandError]
      # @return [String] `"OK"`
      def restore(key, ttl, serialized_value, replace: nil)
        args = [key, ttl, serialized_value]
        args << 'REPLACE' if replace

        send_command(RequestType::RESTORE, args)
      end

      # Transfer a key from the connected instance to another instance.
      #
      # @example Migrate a single key
      #   valkey.migrate("mykey", host: "127.0.0.1", port: 6380)
      #     # => "OK"
      # @example Migrate with copy and replace
      #   valkey.migrate("mykey", host: "127.0.0.1", port: 6380, copy: true, replace: true)
      #     # => "OK"
      # @example Migrate multiple keys
      #   valkey.migrate(["key1", "key2"], host: "127.0.0.1", port: 6380)
      #     # => "OK"
      #
      # @param [String, Array<String>] key single key or array of keys to migrate
      # @param [Hash] options
      #   - `:host => String`: host of instance to migrate to (required)
      #   - `:port => Integer`: port of instance to migrate to (required)
      #   - `:db => Integer`: database to migrate to (default: 0)
      #   - `:timeout => Integer`: timeout in milliseconds (default: 0)
      #   - `:copy => Boolean`: do not remove the key from the local instance
      #   - `:replace => Boolean`: replace existing key on the remote instance
      # @return [String] `"OK"`
      #
      # @see https://valkey.io/commands/migrate/
      def migrate(key, options)
        args = []
        args << (options[:host] || raise(ArgumentError, ':host not specified'))
        args << (options[:port] || raise(ArgumentError, ':port not specified')).to_s
        args << (key.is_a?(String) ? key : '')
        args << (options[:db] || 0).to_s
        args << (options[:timeout] || 0).to_s
        args << 'COPY' if options[:copy]
        args << 'REPLACE' if options[:replace]
        args += ['KEYS', *key] if key.is_a?(Array)

        send_command(RequestType::MIGRATE, args)
      end

      # Find all keys matching the given pattern.
      #
      # @example Find all keys
      #   valkey.keys
      #     # => ["key1", "key2", ...]
      # @example Find keys matching a pattern
      #   valkey.keys("user:*")
      #     # => ["user:1", "user:2"]
      #
      # @param [String] pattern glob-style pattern (default: "*")
      # @return [Array<String>] array of matching keys
      #
      # @see https://valkey.io/commands/keys/
      def keys(pattern = "*")
        send_command(RequestType::KEYS, [pattern]) do |reply|
          if reply.is_a?(String)
            reply.split
          else
            reply
          end
        end
      end

      # Delete one or more keys.
      #
      # @param [String, Array<String>] keys
      # @return [Integer] number of keys that were deleted
      def del(*keys)
        keys.flatten!(1)
        return 0 if keys.empty?

        send_command(RequestType::DEL, keys)
      end

      # Unlink one or more keys.
      #
      # @param [String, Array<String>] keys
      # @return [Integer] number of keys that were unlinked
      def unlink(*keys)
        send_command(RequestType::UNLINK, keys.flatten)
      end

      # Determine how many of the keys exists.
      #
      # @param [String, Array<String>] keys
      # @return [Integer]
      def exists(*keys)
        send_command(RequestType::EXISTS, keys.flatten)
      end

      # Determine if any of the keys exists.
      #
      # @param [String, Array<String>] keys
      # @return [Boolean]
      def exists?(*keys)
        send_command(RequestType::EXISTS, keys.flatten, &:positive?)
      end

      # Move a key to another database.
      #
      # @example Move a key to another database
      #   valkey.set "foo", "bar"
      #     # => "OK"
      #   valkey.move "foo", 2
      #     # => true
      #   valkey.exists "foo"
      #     # => false
      #   valkey.select 2
      #     # => "OK"
      #   valkey.exists "foo"
      #     # => true
      #   valkey.get "foo"
      #     # => "bar"
      #
      # @param [String] key
      # @param [Integer] db
      # @return [Boolean] whether the key was moved or not
      def move(key, db)
        send_command(RequestType::MOVE, [key, db])
      end

      # Copy a value from one key to another.
      #
      # @example Copy a value to another key
      #   valkey.set "foo", "value"
      #     # => "OK"
      #   valkey.copy "foo", "bar"
      #     # => true
      #   valkey.get "bar"
      #     # => "value"
      #
      # @example Copy a value to a key in another database
      #   valkey.set "foo", "value"
      #     # => "OK"
      #   valkey.copy "foo", "bar", db: 2
      #     # => true
      #   valkey.select 2
      #     # => "OK"
      #   valkey.get "bar"
      #     # => "value"
      #
      # @param [String] source
      # @param [String] destination
      # @param [Integer] db
      # @param [Boolean] replace removes the `destination` key before copying value to it
      # @return [Boolean] whether the key was copied or not
      def copy(source, destination, db: nil, replace: false)
        args = [source, destination]
        args << "DB" << db if db
        args << "REPLACE" if replace

        send_command(RequestType::COPY, args)
      end

      def object(subcommand, *args)
        map = {
          refcount: RequestType::OBJECT_REF_COUNT,
          encoding: RequestType::OBJECT_ENCODING,
          idletime: RequestType::OBJECT_IDLE_TIME,
          freq: RequestType::OBJECT_FREQ
        }

        send_command(map[subcommand.to_sym], args.flatten)
      end

      # Return a random key from the keyspace.
      #
      # @return [String]
      def randomkey
        send_command(RequestType::RANDOM_KEY)
      end

      # Rename a key. If the new key already exists it is overwritten.
      #
      # @param [String] old_name
      # @param [String] new_name
      # @return [String] `OK`
      def rename(old_name, new_name)
        send_command(RequestType::RENAME, [old_name, new_name])
      end

      # Rename a key, only if the new key does not exist.
      #
      # @param [String] old_name
      # @param [String] new_name
      # @return [Boolean] whether the key was renamed or not
      def renamenx(old_name, new_name)
        send_command(RequestType::RENAME_NX, [old_name, new_name])
      end

      # Sort the elements in a list, set or sorted set.
      #
      # @example Retrieve the first 2 elements from an alphabetically sorted "list"
      #   valkey.sort("list", :order => "alpha", :limit => [0, 2])
      #     # => ["a", "b"]
      # @example Store an alphabetically descending list in "target"
      #   valkey.sort("list", :order => "desc alpha", :store => "target")
      #     # => 26
      #
      # @param [String] key
      # @param [Hash] options
      #   - `:by => String`: use external key to sort elements by
      #   - `:limit => [offset, count]`: skip `offset` elements, return a maximum
      #   of `count` elements
      #   - `:get => [String, Array<String>]`: single key or array of keys to
      #   retrieve per element in the result
      #   - `:order => String`: combination of `ASC`, `DESC` and optionally `ALPHA`
      #   - `:store => String`: key to store the result at
      #
      # @return [Array<String>, Array<Array<String>>, Integer]
      #   - when `:get` is not specified, or holds a single element, an array of elements
      #   - when `:get` is specified, and holds more than one element, an array of
      #   elements where every element is an array with the result for every
      #   element specified in `:get`
      #   - when `:store` is specified, the number of elements in the stored result
      def sort(key, by: nil, limit: nil, get: nil, order: nil, store: nil)
        args = [key]
        args << "BY" << by if by

        if limit
          args << "LIMIT"
          args.concat(limit)
        end

        get = Array(get)
        get.each do |item|
          args << "GET" << item
        end

        args.concat(order.split) if order
        args << "STORE" << store if store

        send_command(RequestType::SORT, args) do |reply|
          if get.size > 1 && !store
            reply.each_slice(get.size).to_a if reply
          else
            reply
          end
        end
      end

      def touch(*keys)
        send_command(RequestType::TOUCH, keys.flatten)
      end

      # Block until all the previous write commands are successfully transferred
      # and acknowledged by at least the specified number of replicas.
      #
      # @param [Integer] numreplicas minimum number of replicas to acknowledge
      # @param [Integer] timeout timeout in milliseconds (0 means block forever)
      # @return [Integer] number of replicas that acknowledged
      #
      # @example Wait for 1 replica with 1 second timeout
      #   valkey.wait(1, 1000)
      #     # => 1
      #
      # @see https://valkey.io/commands/wait/
      def wait(numreplicas, timeout)
        send_command(RequestType::WAIT, [numreplicas.to_s, timeout.to_s])
      end

      # Block until all previous write commands are fsynced to the AOF of the
      # local server and/or at least the specified number of replicas.
      #
      # @param [Integer] numlocal number of local fsyncs required (0 or 1)
      # @param [Integer] numreplicas minimum number of replicas to fsync
      # @param [Integer] timeout timeout in milliseconds (0 means block forever)
      # @return [Array<Integer>] array of two integers:
      #   - number of local servers (0 or 1) that fsynced
      #   - number of replicas that fsynced
      #
      # @example Wait for local AOF fsync with no timeout
      #   valkey.waitaof(1, 0, 0)
      #     # => [1, 0]
      # @example Wait for 1 replica fsync with 1 second timeout
      #   valkey.waitaof(0, 1, 1000)
      #     # => [0, 0]
      #
      # @see https://valkey.io/commands/waitaof/
      def waitaof(numlocal, numreplicas, timeout)
        send_command(RequestType::WAIT_AOF, [numlocal.to_s, numreplicas.to_s, timeout.to_s])
      end

      # Determine the type stored at key.
      #
      # @param [String] key
      # @return [String] `string`, `list`, `set`, `zset`, `hash` or `none`
      def type(key)
        send_command(RequestType::TYPE, [key])
      end

      def _scan(command, cursor, args, match: nil, count: nil, type: nil, &block)
        # SSCAN/ZSCAN/HSCAN already prepend the key to +args+.

        args << cursor
        args << "MATCH" << match if match
        args << "COUNT" << Integer(count) if count
        args << "TYPE" << type if type

        send_command(command, args, &block)
      end
    end
  end
end
