# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands on the Hash data type.
    #
    # @see https://valkey.io/commands/#hash
    #
    module HashCommands
      # Delete one or more hash fields.
      #
      # @example
      #   valkey.hdel("hash", "field1", "field2")
      #     # => 2
      #
      # @param [String] key
      # @param [String, Array<String>] field one field, or array of fields
      # @return [Integer] the number of fields that were removed
      def hdel(key, *fields)
        fields.flatten!(1)
        send_command(RequestType::HDEL, [key].concat(fields))
      end

      # Determine if a hash field exists.
      #
      # @example
      #   valkey.hexists("hash", "field")
      #     # => true
      #
      # @param [String] key
      # @param [String] field
      # @return [Boolean] whether the field exists
      def hexists(key, field)
        send_command(RequestType::HEXISTS, [key, field], &Utils::Boolify)
      end

      # Get the value of a hash field.
      #
      # @example
      #   valkey.hget("hash", "field")
      #     # => "value"
      #
      # @param [String] key
      # @param [String] field
      # @return [String, nil] the value of the field, or nil if the field does not exist
      def hget(key, field)
        send_command(RequestType::HGET, [key, field])
      end

      # Get all the fields and values in a hash.
      #
      # @example
      #   valkey.hgetall("hash")
      #     # => {"field1" => "value1", "field2" => "value2"}
      #
      # @param [String] key
      # @return [Hash] a hash mapping fields to their values
      def hgetall(key)
        send_command(RequestType::HGET_ALL, [key], &Utils::Hashify)
      end

      # Increment the integer value of a hash field by the given number.
      #
      # @example
      #   valkey.hincrby("hash", "field", 5)
      #     # => 10
      #
      # @param [String] key
      # @param [String] field
      # @param [Integer] increment
      # @return [Integer] value after incrementing it
      def hincrby(key, field, increment)
        send_command(RequestType::HINCR_BY, [key, field, Integer(increment)])
      end

      # Increment the numeric value of a hash field by the given float number.
      #
      # @example
      #   valkey.hincrbyfloat("hash", "field", 1.23)
      #     # => 1.23
      #
      # @param [String] key
      # @param [String] field
      # @param [Float] increment
      # @return [Float] value after incrementing it
      def hincrbyfloat(key, field, increment)
        send_command(RequestType::HINCR_BY_FLOAT, [key, field, Float(increment)], &Utils::Floatify)
      end

      # Get all the fields in a hash.
      #
      # @example
      #   valkey.hkeys("hash")
      #     # => ["field1", "field2"]
      #
      # @param [String] key
      # @return [Array<String>] an array of field names
      def hkeys(key)
        send_command(RequestType::HKEYS, [key])
      end

      # Get the number of fields in a hash.
      #
      # @example
      #   valkey.hlen("hash")
      #     # => 2
      #
      # @param [String] key
      # @return [Integer] the number of fields in the hash
      def hlen(key)
        send_command(RequestType::HLEN, [key])
      end

      # Get the values of all the given hash fields.
      #
      # @example
      #   valkey.hmget("hash", "field1", "field2")
      #     # => ["value1", "value2"]
      #
      # @param [String] key
      # @param [String, Array<String>] field one field, or array of fields
      # @return [Array<String, nil>] an array of values for the specified fields
      #
      # @see #mapped_hmget
      def hmget(key, *fields, &blk)
        fields.flatten!(1)
        send_command(RequestType::HMGET, [key].concat(fields), &blk)
      end

      # Get the values of all the given hash fields.
      #
      # @example
      #   valkey.mapped_hmget("hash", "field1", "field2")
      #     # => {"field1" => "value1", "field2" => "value2"}
      #
      # @param [String] key
      # @param [String, Array<String>] field one field, or array of fields
      # @return [Hash] a hash mapping the specified fields to their values
      #
      # @see #hmget
      def mapped_hmget(key, *fields)
        fields.flatten!(1)
        hmget(key, fields) do |reply|
          if reply.is_a?(Array)
            Hash[fields.zip(reply)]
          else
            reply
          end
        end
      end

      # Set multiple hash fields to multiple values.
      #
      # @example
      #   valkey.hmset("hash", "field1", "value1", "field2", "value2")
      #     # => "OK"
      #
      # @param [String] key
      # @param [Array<String>] args array of field-value pairs
      # @return [String] `"OK"`
      #
      # @see #mapped_hmset
      def hmset(key, *args)
        send_command(RequestType::HMSET, [key].concat(args))
      end

      # Set multiple hash fields to multiple values.
      #
      # @example
      #   valkey.mapped_hmset("hash", { "field1" => "value1", "field2" => "value2" })
      #     # => "OK"
      #
      # @param [String] key
      # @param [Hash] hash fields mapping to values
      # @return [String] `"OK"`
      #
      # @see #hmset
      def mapped_hmset(key, hash)
        hmset(key, *hash.flatten)
      end

      # Get one or multiple random fields from a hash.
      #
      # @example Get one random field
      #   valkey.hrandfield("hash")
      #     # => "field1"
      # @example Get multiple random fields
      #   valkey.hrandfield("hash", 2)
      #     # => ["field1", "field2"]
      # @example Get multiple random fields with values
      #   valkey.hrandfield("hash", 2, with_values: true)
      #     # => [["field1", "value1"], ["field2", "value2"]]
      #
      # @param [String] key
      # @param [Integer] count number of fields to return (optional)
      # @param [Hash] options
      #   - `:with_values => true`: include values in output
      #
      # @return [nil, String, Array<String>, Array<[String, String]>]
      #   - when `key` does not exist, `nil`
      #   - when `count` is not specified, a field name
      #   - when `count` is specified and `:with_values` is not specified, an array of field names
      #   - when `:with_values` is specified, an array with `[field, value]` pairs
      def hrandfield(key, count = nil, withvalues: false, with_values: withvalues)
        raise ArgumentError, "count argument must be specified" if with_values && count.nil?

        args = [key]
        args << Integer(count) if count
        args << "WITHVALUES" if with_values

        if with_values
          send_command(RequestType::HRAND_FIELD, args) do |reply|
            # Handle both ARRAY (flat) and MAP (already pairs) response types
            if reply.is_a?(Array) && !reply.empty? && reply.first.is_a?(Array) && reply.first.size == 2
              # Already in pairs format (from MAP response): [[field, value], ...]
              reply
            elsif reply.is_a?(Array) && reply.respond_to?(:each_slice)
              # ARRAY response: flat array of field-value pairs, convert to pairs
              reply.each_slice(2).to_a
            else
              # Fallback: try Pairify
              Utils::Pairify.call(reply)
            end
          end
        else
          send_command(RequestType::HRAND_FIELD, args)
        end
      end

      # Scan a hash
      #
      # @example Retrieve the first batch of key/value pairs in a hash
      #   valkey.hscan("hash", 0)
      #
      # @param [String] key
      # @param [String, Integer] cursor the cursor of the iteration
      # @param [Hash] options
      #   - `:match => String`: only return fields matching the pattern
      #   - `:count => Integer`: return count fields at most per iteration
      #
      # @return [String, Array<[String, String]>] the next cursor and all found key/value pairs
      #
      # See the [Valkey Server HSCAN documentation](https://valkey.io/commands/hscan/) for further details
      def hscan(key, cursor, **options)
        _scan(RequestType::HSCAN, cursor, [key], **options) do |reply|
          [reply[0], reply[1].each_slice(2).to_a]
        end
      end

      # Scan a hash
      #
      # @example Retrieve all of the key/value pairs in a hash
      #   valkey.hscan_each("hash").to_a
      #   # => [["field1", "value1"], ["field2", "value2"]]
      #
      # @param [String] key
      # @param [Hash] options
      #   - `:match => String`: only return fields matching the pattern
      #   - `:count => Integer`: return count fields at most per iteration
      #
      # @return [Enumerator] an enumerator for all key/value pairs in the hash
      #
      # See the [Valkey Server HSCAN documentation](https://valkey.io/commands/hscan/) for further details
      def hscan_each(key, **options, &block)
        return to_enum(:hscan_each, key, **options) unless block_given?

        cursor = 0
        loop do
          cursor, values = hscan(key, cursor, **options)
          values.each(&block)
          break if cursor == "0"
        end
      end

      # Set one or more hash values.
      #
      # @example
      #   valkey.hset("hash", "f1", "v1", "f2", "v2") # => 2
      #   valkey.hset("hash", { "f1" => "v1", "f2" => "v2" }) # => 2
      #
      # @param [String] key
      # @param [Array<String> | Hash<String, String>] attrs array or hash of fields and values
      # @return [Integer] The number of fields that were added to the hash
      def hset(key, *attrs)
        attrs = attrs.first.flatten if attrs.size == 1 && attrs.first.is_a?(Hash)

        send_command(RequestType::HSET, [key, *attrs])
      end

      # Set the string value of a hash field, only if the field does not exist.
      #
      # @example
      #   valkey.hsetnx("hash", "field", "value")
      #     # => true
      #
      # @param [String] key
      # @param [String] field
      # @param [String] value
      # @return [Boolean] whether the field was set or not
      def hsetnx(key, field, value)
        send_command(RequestType::HSET_NX, [key, field, value], &Utils::Boolify)
      end

      # Get the string length of the value associated with field in the hash stored at key.
      #
      # @example
      #   valkey.hstrlen("hash", "field")
      #     # => 5
      #
      # @param [String] key
      # @param [String] field
      # @return [Integer] the string length of the value associated with field, or 0 when field is not
      #   present in the hash or key does not exist
      def hstrlen(key, field)
        send_command(RequestType::HSTRLEN, [key, field])
      end

      # Get all the values in a hash.
      #
      # @example
      #   valkey.hvals("hash")
      #     # => ["value1", "value2"]
      #
      # @param [String] key
      # @return [Array<String>] an array of values
      def hvals(key)
        send_command(RequestType::HVALS, [key])
      end

      # Set the string value of a hash field and set its expiration time in seconds.
      #
      # @example
      #   valkey.hsetex("hash", "field", "value", 60)
      #     # => 1
      #
      # @param [String] key
      # @param [String] field
      # @param [String] value
      # @param [Integer] seconds expiration time in seconds
      # @return [Integer] the number of fields that were added
      def hsetex(key, field, value, seconds)
        send_command(RequestType::HSETEX, [key, field, value, Integer(seconds)])
      end

      # Get the value of one or more hash fields and optionally set their expiration time.
      #
      # @example
      #   valkey.hgetex("hash", "field1", "field2", ex: 60)
      #     # => ["value1", "value2"]
      #
      # @param [String] key
      # @param [String, Array<String>] fields one field, or array of fields
      # @param [Hash] options
      #   - `:ex => Integer`: Set the specified expire time, in seconds.
      #   - `:px => Integer`: Set the specified expire time, in milliseconds.
      #   - `:exat => Integer`: Set the specified Unix time at which the field will expire, in seconds.
      #   - `:pxat => Integer`: Set the specified Unix time at which the field will expire, in milliseconds.
      #   - `:persist => true`: Remove the time to live associated with the field.
      # @return [String, Array<String, nil>] The value of the field for single field, or array of values
      #   for multiple fields. For every field that does not exist in the hash, a nil value is returned.
      def hgetex(key, *fields, ex: nil, px: nil, exat: nil, pxat: nil, persist: false)
        fields.flatten!(1)
        args = [key, "FIELDS", fields.length, *fields]
        args << "EX" << ex if ex
        args << "PX" << px if px
        args << "EXAT" << exat if exat
        args << "PXAT" << pxat if pxat
        args << "PERSIST" if persist

        send_command(RequestType::HGETEX, args) do |reply|
          fields.length == 1 ? reply[0] : reply
        end
      end

      # Set a timeout on one or more hash fields.
      #
      # @example
      #   valkey.hexpire("hash", 60, "field1", "field2")
      #     # => [1, 1]
      #
      # @param [String] key
      # @param [Integer] seconds time to live in seconds
      # @param [String, Array<String>] fields one field, or array of fields
      # @param [Hash] options
      #   - `:nx => true`: Set expiry only when the field has no expiry.
      #   - `:xx => true`: Set expiry only when the field has an existing expiry.
      #   - `:gt => true`: Set expiry only when the new expiry is greater than current one.
      #   - `:lt => true`: Set expiry only when the new expiry is less than current one.
      # @return [Array<Integer>] Array of results for each field.
      #   - `1` if the expiration time was successfully set for the field.
      #   - `0` if the specified condition was not met.
      #   - `-2` if the field does not exist in the HASH, or key does not exist.
      def hexpire(key, seconds, *fields, nx: nil, xx: nil, gt: nil, lt: nil)
        fields.flatten!(1)
        args = [key, Integer(seconds), "FIELDS", fields.length, *fields]
        args << "NX" if nx
        args << "XX" if xx
        args << "GT" if gt
        args << "LT" if lt

        send_command(RequestType::HEXPIRE, args)
      end

      # Set the expiration for one or more hash fields as a UNIX timestamp.
      #
      # @example
      #   valkey.hexpireat("hash", Time.now.to_i + 60, "field1", "field2")
      #     # => [1, 1]
      #
      # @param [String] key
      # @param [Integer] unix_time expiry time specified as a UNIX timestamp in seconds
      # @param [String, Array<String>] fields one field, or array of fields
      # @param [Hash] options
      #   - `:nx => true`: Set expiry only when the field has no expiry.
      #   - `:xx => true`: Set expiry only when the field has an existing expiry.
      #   - `:gt => true`: Set expiry only when the new expiry is greater than current one.
      #   - `:lt => true`: Set expiry only when the new expiry is less than current one.
      # @return [Array<Integer>] Array of results for each field.
      #   - `1` if the expiration time was successfully set for the field.
      #   - `0` if the specified condition was not met.
      #   - `-2` if the field does not exist in the HASH, or key does not exist.
      def hexpireat(key, unix_time, *fields, nx: nil, xx: nil, gt: nil, lt: nil)
        fields.flatten!(1)
        args = [key, Integer(unix_time), "FIELDS", fields.length, *fields]
        args << "NX" if nx
        args << "XX" if xx
        args << "GT" if gt
        args << "LT" if lt

        send_command(RequestType::HEXPIREAT, args)
      end

      # Set a timeout on one or more hash fields in milliseconds.
      #
      # @example
      #   valkey.hpexpire("hash", 60000, "field1", "field2")
      #     # => [1, 1]
      #
      # @param [String] key
      # @param [Integer] milliseconds time to live in milliseconds
      # @param [String, Array<String>] fields one field, or array of fields
      # @param [Hash] options
      #   - `:nx => true`: Set expiry only when the field has no expiry.
      #   - `:xx => true`: Set expiry only when the field has an existing expiry.
      #   - `:gt => true`: Set expiry only when the new expiry is greater than current one.
      #   - `:lt => true`: Set expiry only when the new expiry is less than current one.
      # @return [Array<Integer>] Array of results for each field.
      #   - `1` if the expiration time was successfully set for the field.
      #   - `0` if the specified condition was not met.
      #   - `-2` if the field does not exist in the HASH, or key does not exist.
      def hpexpire(key, milliseconds, *fields, nx: nil, xx: nil, gt: nil, lt: nil)
        fields.flatten!(1)
        args = [key, Integer(milliseconds), "FIELDS", fields.length, *fields]
        args << "NX" if nx
        args << "XX" if xx
        args << "GT" if gt
        args << "LT" if lt

        send_command(RequestType::HPEXPIRE, args)
      end

      # Set the expiration for one or more hash fields as a UNIX timestamp in milliseconds.
      #
      # @example
      #   valkey.hpexpireat("hash", (Time.now.to_i * 1000) + 60000, "field1", "field2")
      #     # => [1, 1]
      #
      # @param [String] key
      # @param [Integer] unix_time_ms expiry time specified as a UNIX timestamp in milliseconds
      # @param [String, Array<String>] fields one field, or array of fields
      # @param [Hash] options
      #   - `:nx => true`: Set expiry only when the field has no expiry.
      #   - `:xx => true`: Set expiry only when the field has an existing expiry.
      #   - `:gt => true`: Set expiry only when the new expiry is greater than current one.
      #   - `:lt => true`: Set expiry only when the new expiry is less than current one.
      # @return [Array<Integer>] Array of results for each field.
      #   - `1` if the expiration time was successfully set for the field.
      #   - `0` if the specified condition was not met.
      #   - `-2` if the field does not exist in the HASH, or key does not exist.
      def hpexpireat(key, unix_time_ms, *fields, nx: nil, xx: nil, gt: nil, lt: nil)
        fields.flatten!(1)
        args = [key, Integer(unix_time_ms), "FIELDS", fields.length, *fields]
        args << "NX" if nx
        args << "XX" if xx
        args << "GT" if gt
        args << "LT" if lt

        send_command(RequestType::HPEXPIREAT, args)
      end

      # Remove the expiration from one or more hash fields.
      #
      # @example
      #   valkey.hpersist("hash", "field1", "field2")
      #     # => [1, 1]
      #
      # @param [String] key
      # @param [String, Array<String>] fields one field, or array of fields
      # @return [Array<Integer>] Array of results for each field.
      #   - `1` if the expiration time was successfully removed from the field.
      #   - `-1` if the field exists but has no expiration time.
      #   - `-2` if the field does not exist in the provided hash key, or the hash key does not exist.
      def hpersist(key, *fields)
        fields.flatten!(1)
        args = [key, "FIELDS", fields.length, *fields]

        send_command(RequestType::HPERSIST, args)
      end

      # Get the time to live in seconds of one or more hash fields.
      #
      # @example
      #   valkey.httl("hash", "field1", "field2")
      #     # => [60, -1]
      #
      # @param [String] key
      # @param [String, Array<String>] fields one field, or array of fields
      # @return [Array<Integer>] Array of TTLs in seconds for each field.
      #   - TTL in seconds if the field exists and has a timeout.
      #   - `-1` if the field exists but has no associated expire.
      #   - `-2` if the field does not exist in the provided hash key, or the hash key is empty.
      def httl(key, *fields)
        fields.flatten!(1)
        args = [key, "FIELDS", fields.length, *fields]

        send_command(RequestType::HTTL, args)
      end

      # Get the time to live in milliseconds of one or more hash fields.
      #
      # @example
      #   valkey.hpttl("hash", "field1", "field2")
      #     # => [60000, -1]
      #
      # @param [String] key
      # @param [String, Array<String>] fields one field, or array of fields
      # @return [Array<Integer>] Array of TTLs in milliseconds for each field.
      #   - TTL in milliseconds if the field exists and has a timeout.
      #   - `-1` if the field exists but has no associated expire.
      #   - `-2` if the field does not exist in the provided hash key, or the hash key is empty.
      def hpttl(key, *fields)
        fields.flatten!(1)
        args = [key, "FIELDS", fields.length, *fields]

        send_command(RequestType::HPTTL, args)
      end

      # Get the expiration Unix timestamp in seconds for one or more hash fields.
      #
      # @example
      #   valkey.hexpiretime("hash", "field1", "field2")
      #     # => [1234567890, -1]
      #
      # @param [String] key
      # @param [String, Array<String>] fields one field, or array of fields
      # @return [Array<Integer>] Array of expiration timestamps in seconds for each field.
      #   - Expiration Unix timestamp in seconds if the field exists and has a timeout.
      #   - `-1` if the field exists but has no associated expire.
      #   - `-2` if the field does not exist in the provided hash key, or the hash key is empty.
      def hexpiretime(key, *fields)
        fields.flatten!(1)
        args = [key, "FIELDS", fields.length, *fields]

        send_command(RequestType::HEXPIRETIME, args)
      end

      # Get the expiration Unix timestamp in milliseconds for one or more hash fields.
      #
      # @example
      #   valkey.hpexpiretime("hash", "field1", "field2")
      #     # => [1234567890000, -1]
      #
      # @param [String] key
      # @param [String, Array<String>] fields one field, or array of fields
      # @return [Array<Integer>] Array of expiration timestamps in milliseconds for each field.
      #   - Expiration Unix timestamp in milliseconds if the field exists and has a timeout.
      #   - `-1` if the field exists but has no associated expire.
      #   - `-2` if the field does not exist in the provided hash key, or the hash key is empty.
      def hpexpiretime(key, *fields)
        fields.flatten!(1)
        args = [key, "FIELDS", fields.length, *fields]

        send_command(RequestType::HPEXPIRETIME, args)
      end
    end
  end
end
