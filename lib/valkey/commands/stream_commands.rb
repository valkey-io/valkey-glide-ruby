# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands related to Redis Streams.
    #
    # @see https://valkey.io/commands/#stream
    #
    module StreamCommands
      # Append a new entry to a stream.
      #
      # @param [String] key stream key
      # @param [Hash, Array] entry field-value pairs
      # @param [Hash] options optional parameters
      #   - `:id => String`: entry ID (default: "*" for auto-generated)
      #   - `:maxlen => Integer`: maximum length of the stream
      #   - `:minid => String`: minimum ID to keep
      #   - `:approximate => true`: use approximate trimming
      #   - `:nomkstream => true`: do not create stream if it doesn't exist
      # @return [String] entry ID
      #
      # @example Add entry with auto-generated ID
      #   valkey.xadd("mystream", { "field1" => "value1", "field2" => "value2" })
      #     # => "1234567890-0"
      # @example Add entry with specific ID
      #   valkey.xadd("mystream", { "field1" => "value1" }, id: "1234567890-1")
      #     # => "1234567890-1"
      # @example Add entry with maxlen trimming
      #   valkey.xadd("mystream", { "field1" => "value1" }, maxlen: 1000, approximate: true)
      #
      # @see https://valkey.io/commands/xadd/
      def xadd(key, entry, approximate: nil, maxlen: nil, minid: nil, nomkstream: nil, id: "*")
        args = [key]

        # Handle maxlen/minid trimming
        if maxlen
          raise ArgumentError, "can't supply both maxlen and minid" if minid

          args << "MAXLEN"
          args << "~" if approximate
          args << maxlen.to_s
        elsif minid
          args << "MINID"
          args << "~" if approximate
          args << minid
        end

        args << "NOMKSTREAM" if nomkstream
        args << id

        # Add field-value pairs
        if entry.is_a?(Hash)
          entry.each { |k, v| args << k.to_s << v.to_s }
        else
          args.concat(Array(entry).flatten)
        end

        send_command(RequestType::X_ADD, args)
      end

      # Remove one or more entries from a stream.
      #
      # @param [String] key stream key
      # @param [String, Array<String>] ids entry ID(s) to delete
      # @return [Integer] number of entries deleted
      #
      # @example Delete a single entry
      #   valkey.xdel("mystream", "1234567890-0")
      #     # => 1
      # @example Delete multiple entries
      #   valkey.xdel("mystream", ["1234567890-0", "1234567890-1"])
      #     # => 2
      #
      # @see https://valkey.io/commands/xdel/
      def xdel(key, *ids)
        args = [key] + Array(ids).flatten
        send_command(RequestType::X_DEL, args)
      end

      # Get the length of a stream.
      #
      # @param [String] key stream key
      # @return [Integer] number of entries in the stream
      #
      # @example
      #   valkey.xlen("mystream")
      #     # => 42
      #
      # @see https://valkey.io/commands/xlen/
      def xlen(key)
        send_command(RequestType::X_LEN, [key])
      end

      # Read entries from one or more streams.
      #
      # @param [Array<String>] keys stream keys
      # @param [Array<String>] ids last read IDs for each stream
      # @param [Hash] options optional parameters
      #   - `:count => Integer`: maximum number of entries per stream
      #   - `:block => Integer`: block for specified milliseconds (0 = no timeout)
      # @return [Hash] hash of stream keys to arrays of entries (empty hash on timeout or no data)
      #
      # @example Read from a single stream
      #   valkey.xread(["mystream"], ["0"])
      #     # => { "mystream" => [["1234567890-0", ["field1", "value1"]]] }
      # @example Read with count and block
      #   valkey.xread(["mystream"], ["0"], count: 10, block: 1000)
      #
      # @see https://valkey.io/commands/xread/
      def xread(keys, ids, count: nil, block: nil)
        args = []

        args << "COUNT" << count.to_s if count
        args << "BLOCK" << block.to_s if block
        args << "STREAMS"
        args.concat(Array(keys))
        args.concat(Array(ids))

        send_command(RequestType::X_READ, args) do |reply|
          # Backend returns Array format: [stream_name, entries, stream_name2, entries2, ...]
          # Convert to Hash format first
          if reply.nil?
            {}
          elsif reply.is_a?(Array) && !reply.empty?
            stream_hash = reply.each_slice(2).to_h
            Utils::HashifyStreams.call(stream_hash)
          else
            Utils::HashifyStreams.call(reply)
          end
        end
      end

      # Read entries from streams using a consumer group.
      #
      # @param [String] group consumer group name
      # @param [String] consumer consumer name
      # @param [Array<String>] keys stream keys
      # @param [Array<String>] ids last read IDs for each stream
      # @param [Hash] options optional parameters
      #   - `:count => Integer`: maximum number of entries per stream
      #   - `:block => Integer`: block for specified milliseconds (0 = no timeout)
      #   - `:noack => true`: do not add messages to pending list
      # @return [Hash] hash of stream keys to arrays of entries (empty hash on timeout or no data)
      #
      # @example Read from consumer group
      #   valkey.xreadgroup("mygroup", "consumer1", ["mystream"], [">"])
      #
      # @see https://valkey.io/commands/xreadgroup/
      def xreadgroup(group, consumer, keys, ids, count: nil, block: nil, noack: false)
        args = ["GROUP", group, consumer]

        args << "COUNT" << count.to_s if count
        args << "BLOCK" << block.to_s if block
        args << "NOACK" if noack
        args << "STREAMS"
        args.concat(Array(keys))
        args.concat(Array(ids))

        send_command(RequestType::X_READ_GROUP, args) do |reply|
          # Backend returns Array format: [stream_name, entries, stream_name2, entries2, ...]
          # Convert to Hash format first
          if reply.nil?
            {}
          elsif reply.is_a?(Array) && !reply.empty?
            stream_hash = reply.each_slice(2).to_h
            Utils::HashifyStreams.call(stream_hash)
          else
            Utils::HashifyStreams.call(reply)
          end
        end
      end

      # Get entries from a stream within a range of IDs.
      #
      # @param [String] key stream key
      # @param [String] start start ID ("-" for beginning, "+" for end)
      # @param [String] end_id end ID ("-" for beginning, "+" for end)
      # @param [Hash] options optional parameters
      #   - `:count => Integer`: maximum number of entries to return
      # @return [Array] array of [id, [field, value, ...]] entries
      #
      # @example Get all entries
      #   valkey.xrange("mystream", "-", "+")
      # @example Get entries with count limit
      #   valkey.xrange("mystream", "-", "+", count: 10)
      #
      # @see https://valkey.io/commands/xrange/
      def xrange(key, start, end_id, **options)
        args = [key, start, end_id]
        args << "COUNT" << options[:count].to_s if options[:count]
        send_command(RequestType::X_RANGE, args) do |reply|
          Utils::HashifyStreamEntries.call(reply)
        end
      end

      # Get entries from a stream within a range of IDs in reverse order.
      #
      # @param [String] key stream key
      # @param [String] end_id end ID ("+" for end, "-" for beginning) - higher bound
      # @param [String] start start ID ("-" for beginning, "+" for end) - lower bound
      # @param [Hash] options optional parameters
      #   - `:count => Integer`: maximum number of entries to return
      # @return [Array] array of [id, [field, value, ...]] entries in reverse order
      #
      # @example Get last 10 entries
      #   valkey.xrevrange("mystream", "+", "-", count: 10)
      #
      # @see https://valkey.io/commands/xrevrange/
      def xrevrange(key, end_id = "+", start = "-", count: nil)
        args = [key, end_id, start]
        args << "COUNT" << count.to_s if count
        send_command(RequestType::X_REV_RANGE, args) do |reply|
          Utils::HashifyStreamEntries.call(reply)
        end
      end

      # Trim a stream to a maximum length.
      #
      # @param [String] key stream key
      # @param [Integer] maxlen maximum length of the stream
      # @param [Hash] options trimming options
      #   - `:strategy => String`: trimming strategy (default: "MAXLEN")
      #   - `:approximate => true`: use approximate trimming (default: true)
      # @return [Integer] number of entries removed
      #
      # @example Trim to maximum length
      #   valkey.xtrim("mystream", 1000)
      # @example Trim with exact count
      #   valkey.xtrim("mystream", 1000, approximate: false)
      #
      # @see https://valkey.io/commands/xtrim/
      def xtrim(key, maxlen, strategy: "MAXLEN", approximate: true)
        args = [key, strategy]
        args << "~" if approximate
        args << maxlen.to_s
        send_command(RequestType::X_TRIM, args)
      end

      # Manage consumer groups (dispatcher method).
      #
      # @param [Symbol, String] subcommand subcommand (:create, :setid, :destroy, :createconsumer, :delconsumer)
      # @param [String] key stream key
      # @param [String] group consumer group name
      # @param [Array] args additional arguments depending on subcommand
      # @return [String, Integer] depends on subcommand
      #
      # @example Create group
      #   valkey.xgroup(:create, "mystream", "mygroup", "0")
      # @example Create group with mkstream
      #   valkey.xgroup(:create, "mystream", "mygroup", "0", mkstream: true)
      # @example Set group ID
      #   valkey.xgroup(:setid, "mystream", "mygroup", "1234567890-0")
      # @example Destroy group
      #   valkey.xgroup(:destroy, "mystream", "mygroup")
      # @example Create consumer
      #   valkey.xgroup(:createconsumer, "mystream", "mygroup", "consumer1")
      # @example Delete consumer
      #   valkey.xgroup(:delconsumer, "mystream", "mygroup", "consumer1")
      #
      # @see https://valkey.io/commands/xgroup/
      def xgroup(subcommand, key, group, *args, **options)
        subcommand = subcommand.to_s.downcase
        case subcommand
        when "create"
          xgroup_create(key, group, args[0], **options)
        when "setid"
          xgroup_setid(key, group, args[0])
        when "destroy"
          xgroup_destroy(key, group)
        when "createconsumer"
          xgroup_createconsumer(key, group, args[0])
        when "delconsumer"
          xgroup_delconsumer(key, group, args[0])
        else
          raise ArgumentError, "Unknown XGROUP subcommand: #{subcommand}"
        end
      end

      private

      def xgroup_create_impl(key, group, id, **options)
        args = [key, group, id]
        args << "MKSTREAM" if options[:mkstream]
        send_command(RequestType::X_GROUP_CREATE, args)
      end

      public

      # Create a consumer group for a stream.
      #
      # @param [String] key stream key
      # @param [String] group consumer group name
      # @param [String] id starting ID ("0" for beginning, "$" for end)
      # @param [Hash] options optional parameters
      #   - `:mkstream => true`: create stream if it doesn't exist
      # @return [String] "OK"
      #
      # @example Create group from beginning
      #   valkey.xgroup_create("mystream", "mygroup", "0")
      # @example Create group from end and create stream if needed
      #   valkey.xgroup_create("mystream", "mygroup", "$", mkstream: true)
      #
      # @see https://valkey.io/commands/xgroup-create/
      def xgroup_create(key, group, id, **options)
        xgroup_create_impl(key, group, id, **options)
      end

      # Create a consumer in a consumer group.
      #
      # @param [String] key stream key
      # @param [String] group consumer group name
      # @param [String] consumer consumer name
      # @return [Integer] number of pending messages for the consumer (0 for new consumer)
      #
      # @example
      #   valkey.xgroup_createconsumer("mystream", "mygroup", "consumer1")
      #     # => 0
      #
      # @see https://valkey.io/commands/xgroup-createconsumer/
      def xgroup_createconsumer(key, group, consumer)
        send_command(RequestType::X_GROUP_CREATE_CONSUMER, [key, group, consumer]) do |reply|
          # Convert boolean to integer if needed (backend may return boolean)
          if reply.is_a?(TrueClass)
            1
          elsif reply.is_a?(FalseClass)
            0
          else
            reply
          end
        end
      end

      # Set the last-delivered ID for a consumer group.
      #
      # @param [String] key stream key
      # @param [String] group consumer group name
      # @param [String] id entry ID
      # @return [String] "OK"
      #
      # @example
      #   valkey.xgroup_setid("mystream", "mygroup", "1234567890-0")
      #
      # @see https://valkey.io/commands/xgroup-setid/
      def xgroup_setid(key, group, id)
        send_command(RequestType::X_GROUP_SET_ID, [key, group, id])
      end

      # Destroy a consumer group.
      #
      # @param [String] key stream key
      # @param [String] group consumer group name
      # @return [Integer] number of pending messages (if any)
      #
      # @example
      #   valkey.xgroup_destroy("mystream", "mygroup")
      #     # => 0
      #
      # @see https://valkey.io/commands/xgroup-destroy/
      def xgroup_destroy(key, group)
        send_command(RequestType::X_GROUP_DESTROY, [key, group]) do |reply|
          # Convert boolean to integer if needed (backend may return boolean)
          if reply.is_a?(TrueClass)
            1
          elsif reply.is_a?(FalseClass)
            0
          else
            reply
          end
        end
      end

      # Remove a consumer from a consumer group.
      #
      # @param [String] key stream key
      # @param [String] group consumer group name
      # @param [String] consumer consumer name
      # @return [Integer] number of pending messages for the consumer
      #
      # @example
      #   valkey.xgroup_delconsumer("mystream", "mygroup", "consumer1")
      #     # => 5
      #
      # @see https://valkey.io/commands/xgroup-delconsumer/
      def xgroup_delconsumer(key, group, consumer)
        send_command(RequestType::X_GROUP_DEL_CONSUMER, [key, group, consumer])
      end

      # Acknowledge one or more messages in a consumer group.
      #
      # @param [String] key stream key
      # @param [String] group consumer group name
      # @param [String, Array<String>] ids entry ID(s) to acknowledge
      # @return [Integer] number of messages acknowledged
      #
      # @example Acknowledge a single message
      #   valkey.xack("mystream", "mygroup", "1234567890-0")
      #     # => 1
      # @example Acknowledge multiple messages
      #   valkey.xack("mystream", "mygroup", ["1234567890-0", "1234567890-1"])
      #     # => 2
      #
      # @see https://valkey.io/commands/xack/
      def xack(key, group, *ids)
        args = [key, group] + Array(ids).flatten
        send_command(RequestType::X_ACK, args)
      end

      # Get information about pending messages in a consumer group.
      #
      # @param [String] key stream key
      # @param [String] group consumer group name
      # @param [Array] args optional arguments (start, end, count, consumer)
      # @param [Hash] options optional parameters
      #   - `:idle => Integer`: filter by minimum idle time in milliseconds
      # @return [Hash, Array] pending information
      #   - Without args: summary hash with keys 'size', 'min_entry_id', 'max_entry_id', 'consumers'
      #   - With start/end/count: array of Hashes with keys 'entry_id', 'consumer', 'elapsed', and 'count'
      #
      # @example Get summary
      #   valkey.xpending("mystream", "mygroup")
      #     # => {"size" => 5, "min_entry_id" => "1234567890-0",
      #     #     "max_entry_id" => "1234567890-4", "consumers" => {"consumer1" => 3, "consumer2" => 2}}
      # @example Get detailed pending entries
      #   valkey.xpending("mystream", "mygroup", "-", "+", 10)
      #
      # @see https://valkey.io/commands/xpending/
      def xpending(key, group, *args, idle: nil)
        cmd_args = [key, group]
        cmd_args.concat(args)
        cmd_args << "IDLE" << idle.to_s if idle

        send_command(RequestType::X_PENDING, cmd_args) do |reply|
          # If args provided (start, end, count), return detailed format
          # Otherwise return summary format
          if args.length >= 2
            Utils::HashifyStreamPendingDetails.call(reply)
          else
            Utils::HashifyStreamPendings.call(reply)
          end
        end
      end

      # Claim ownership of pending messages in a consumer group.
      #
      # @param [String] key stream key
      # @param [String] group consumer group name
      # @param [String] consumer consumer name
      # @param [Integer] min_idle_time minimum idle time in milliseconds
      # @param [String, Array<String>] ids entry ID(s) to claim
      # @param [Hash] options optional parameters
      #   - `:idle => Integer`: set idle time in milliseconds
      #   - `:time => Integer`: set time in milliseconds (Unix timestamp)
      #   - `:retrycount => Integer`: set retry count
      #   - `:force => true`: claim even if already assigned
      #   - `:justid => true`: return only IDs
      # @return [Array] array of claimed entries or IDs
      #
      # @example Claim pending messages
      #   valkey.xclaim("mystream", "mygroup", "consumer2", 3600000, ["1234567890-0"])
      #
      # @see https://valkey.io/commands/xclaim/
      def xclaim(key, group, consumer, min_idle_time, ids, **options)
        args = [key, group, consumer, min_idle_time.to_s]
        args.concat(Array(ids).flatten)

        args << "IDLE" << options[:idle].to_s if options[:idle]
        args << "TIME" << options[:time].to_s if options[:time]
        args << "RETRYCOUNT" << options[:retrycount].to_s if options[:retrycount]
        args << "FORCE" if options[:force]
        args << "JUSTID" if options[:justid]

        send_command(RequestType::X_CLAIM, args) do |reply|
          if options[:justid]
            reply
          else
            Utils::HashifyStreamEntries.call(reply)
          end
        end
      end

      # Automatically claim pending messages that have been idle for a specified time.
      #
      # @param [String] key stream key
      # @param [String] group consumer group name
      # @param [String] consumer consumer name
      # @param [Integer] min_idle_time minimum idle time in milliseconds
      # @param [String] start start ID for scanning
      # @param [Hash] options optional parameters
      #   - `:count => Integer`: maximum number of entries to claim
      #   - `:idle => Integer`: set idle time in milliseconds
      #   - `:time => Integer`: set time in milliseconds (Unix timestamp)
      #   - `:retrycount => Integer`: set retry count
      #   - `:justid => true`: return only IDs
      # @return [Hash] hash with 'next' key for next cursor ID and 'entries' key for array of claimed entries
      #
      # @example Auto-claim pending messages
      #   valkey.xautoclaim("mystream", "mygroup", "consumer2", 3600000, "0-0")
      #     # => { 'next' => "1234567890-5", 'entries' => [["1234567890-0", ["field1", "value1"]]] }
      #
      # @see https://valkey.io/commands/xautoclaim/
      def xautoclaim(key, group, consumer, min_idle_time, start, **options)
        args = [key, group, consumer, min_idle_time.to_s, start]

        args << "COUNT" << options[:count].to_s if options[:count]
        args << "IDLE" << options[:idle].to_s if options[:idle]
        args << "TIME" << options[:time].to_s if options[:time]
        args << "RETRYCOUNT" << options[:retrycount].to_s if options[:retrycount]
        args << "JUSTID" if options[:justid]

        send_command(RequestType::X_AUTO_CLAIM, args) do |reply|
          return { 'next' => '0-0', 'entries' => [] } if reply.nil? || !reply.is_a?(Array)

          if options[:justid]
            Utils::HashifyStreamAutoclaimJustId.call(reply)
          else
            Utils::HashifyStreamAutoclaim.call(reply)
          end
        end
      end

      # Get information about streams, groups, and consumers (dispatcher method).
      #
      # @param [Symbol, String] subcommand subcommand (:stream, :groups, :consumers)
      # @param [String] key stream key
      # @param [String] group optional consumer group name (required for :consumers)
      # @param [Hash] options optional parameters (for :stream)
      #   - `:full => true`: return full information including entries
      #   - `:count => Integer`: limit number of entries (requires :full)
      # @return [Hash, Array] depends on subcommand
      #
      # @example Get stream info
      #   valkey.xinfo(:stream, "mystream")
      # @example Get stream info with full details
      #   valkey.xinfo(:stream, "mystream", full: true, count: 10)
      # @example Get groups info
      #   valkey.xinfo(:groups, "mystream")
      # @example Get consumers info
      #   valkey.xinfo(:consumers, "mystream", "mygroup")
      #
      # @see https://valkey.io/commands/xinfo/
      def xinfo(subcommand, key, group = nil, **options)
        subcommand = subcommand.to_s.downcase
        case subcommand
        when "stream"
          args = [key]
          if options[:full]
            args << "FULL"
            args << "COUNT" << options[:count].to_s if options[:count]
          end
          send_command(RequestType::X_INFO_STREAM, args)
        when "groups"
          send_command(RequestType::X_INFO_GROUPS, [key])
        when "consumers"
          raise ArgumentError, "Group name required for XINFO CONSUMERS" unless group

          send_command(RequestType::X_INFO_CONSUMERS, [key, group])
        else
          raise ArgumentError, "Unknown XINFO subcommand: #{subcommand}"
        end
      end

      # Get information about a stream.
      #
      # @param [String] key stream key
      # @param [Hash] options optional parameters
      #   - `:full => true`: return full information including entries
      #   - `:count => Integer`: limit number of entries (requires :full)
      # @return [Array] stream information as flat array of key-value pairs
      #
      # @example Get basic stream info
      #   valkey.xinfo_stream("mystream")
      #     # => ["length", 42, "radix-tree-keys", 1, ...]
      # @example Get full info with entries
      #   valkey.xinfo_stream("mystream", full: true, count: 10)
      #
      # @see https://valkey.io/commands/xinfo-stream/
      def xinfo_stream(key, **options)
        xinfo(:stream, key, **options)
      end

      # Get information about consumer groups of a stream.
      #
      # @param [String] key stream key
      # @return [Array] array of consumer group information hashes
      #
      # @example
      #   valkey.xinfo_groups("mystream")
      #     # => [{"name" => "mygroup", "consumers" => 2, "pending" => 5, ...}]
      #
      # @see https://valkey.io/commands/xinfo-groups/
      def xinfo_groups(key)
        xinfo(:groups, key)
      end

      # Get information about consumers in a consumer group.
      #
      # @param [String] key stream key
      # @param [String] group consumer group name
      # @return [Array] array of consumer information hashes
      #
      # @example
      #   valkey.xinfo_consumers("mystream", "mygroup")
      #     # => [{"name" => "consumer1", "pending" => 3, "idle" => 12345, ...}]
      #
      # @see https://valkey.io/commands/xinfo-consumers/
      def xinfo_consumers(key, group)
        xinfo(:consumers, key, group)
      end

      # TODO: Implement xsetid command after enabling in glide-core
      # Set the ID of the last entry in a stream.
      #
      # @param [String] key stream key
      # @param [String] id entry ID
      # @param [Hash] options optional parameters
      #   - `:entries_added => Integer`: set entries-added counter
      #   - `:max_deleted_id => String`: set max-deleted-id
      # @return [String] "OK"
      #
      # @example
      #   valkey.xsetid("mystream", "1234567890-0")
      # @example With additional options
      #   valkey.xsetid("mystream", "1234567890-0", entries_added: 100, max_deleted_id: "1234567890-50")
      #
      # @see https://valkey.io/commands/xsetid/
      # def xsetid(key, id, **options)
      #   args = [key, id]

      #   args << "ENTRIESADDED" << options[:entries_added].to_s if options[:entries_added]
      #   args << "MAXDELETEDID" << options[:max_deleted_id] if options[:max_deleted_id]

      #   send_command(RequestType::X_SET_ID, args)
      # end
    end
  end
end
