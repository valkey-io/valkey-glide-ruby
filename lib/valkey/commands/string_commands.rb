# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands on the String data type.
    #
    # @see https://valkey.io/commands/#string
    #
    module StringCommands
      # Decrement the integer value of a key by one.
      #
      # @example
      #   valkey.decr("value")
      #     # => 4
      #
      # @param [String] key
      # @return [Integer] value after decrementing it
      def decr(key)
        send_command(RequestType::DECR, [key])
      end

      # Decrement the integer value of a key by the given number.
      #
      # @example
      #   valkey.decrby("value", 5)
      #     # => 0
      #
      # @param [String] key
      # @param [Integer] decrement
      # @return [Integer] value after decrementing it
      def decrby(key, decrement)
        send_command(RequestType::DECR_BY, [key, decrement])
      end

      # Increment the integer value of a key by one.
      #
      # @example
      #   valkey.incr("value")
      #     # => 6
      #
      # @param [String] key
      # @return [Integer] value after incrementing it
      def incr(key)
        send_command(RequestType::INCR, [key])
      end

      # Increment the integer value of a key by the given integer number.
      #
      # @example
      #   valkey.incrby("value", 5)
      #     # => 10
      #
      # @param [String] key
      # @param [Integer] increment
      # @return [Integer] value after incrementing it
      def incrby(key, increment)
        send_command(RequestType::INCR_BY, [key, increment])
      end

      # Increment the numeric value of a key by the given float number.
      #
      # @example
      #   valkey.incrbyfloat("value", 1.23)
      #     # => 1.23
      #
      # @param [String] key
      # @param [Float] increment
      # @return [Float] value after incrementing it
      def incrbyfloat(key, increment)
        send_command(RequestType::INCR_BY_FLOAT, [key, increment])
      end

      # Set the string value of a key.
      #
      # @param [String] key
      # @param [String] value
      # @param [Hash] options
      #   - `:ex => Integer`: Set the specified expire time, in seconds.
      #   - `:px => Integer`: Set the specified expire time, in milliseconds.
      #   - `:exat => Integer` : Set the specified Unix time at which the key will expire, in seconds.
      #   - `:pxat => Integer` : Set the specified Unix time at which the key will expire, in milliseconds.
      #   - `:nx => true`: Only set the key if it does not already exist.
      #   - `:xx => true`: Only set the key if it already exist.
      #   - `:keepttl => true`: Retain the time to live associated with the key.
      #   - `:get => true`: Return the old string stored at key, or nil if key did not exist.
      # @return [String, Boolean] `"OK"` or true, false if `:nx => true` or `:xx => true`
      def set(key, value, ex: nil, px: nil, exat: nil, pxat: nil, nx: nil, xx: nil, keepttl: nil, get: nil)
        args = [key, value]
        args << "EX" << ex if ex
        args << "PX" << px if px
        args << "EXAT" << exat if exat
        args << "PXAT" << pxat if pxat
        args << "NX" if nx
        args << "XX" if xx
        args << "KEEPTTL" if keepttl
        args << "GET" if get

        send_command(RequestType::SET, args)
        # if nx || xx
        #   send_command(RequestType::SET, &BoolifySet))
        # else
        #   send_command(RequestType::SET, args)
        # end
      end

      # Set the time to live in seconds of a key.
      #
      # @param [String] key
      # @param [Integer] ttl
      # @param [String] value
      # @return [String] `"OK"`
      def setex(key, ttl, value)
        send_command(RequestType::SET_EX, [key, ttl, value])
      end

      # Set the time to live in milliseconds of a key.
      #
      # @param [String] key
      # @param [Integer] ttl
      # @param [String] value
      # @return [String] `"OK"`
      def psetex(key, ttl, value)
        send_command(RequestType::PSET_EX, [key, Integer(ttl), value])
      end

      # Set the value of a key, only if the key does not exist.
      #
      # @param [String] key
      # @param [String] value
      # @return [Boolean] whether the key was set or not
      def setnx(key, value)
        send_command(RequestType::SET_NX, [key, value])
      end

      # Set one or more values.
      #
      # @example
      #   valkey.mset("key1", "v1", "key2", "v2")
      #     # => "OK"
      #
      # @param [Array<String>] args array of keys and values
      # @return [String] `"OK"`
      #
      # @see #mapped_mset
      def mset(*args)
        send_command(RequestType::MSET, args)
      end

      # Set one or more values.
      #
      # @example
      #   valkey.mapped_mset({ "f1" => "v1", "f2" => "v2" })
      #     # => "OK"
      #
      # @param [Hash] hash keys mapping to values
      # @return [String] `"OK"`
      #
      # @see #mset
      def mapped_mset(hash)
        mset(*hash.flatten)
      end

      # Set one or more values, only if none of the keys exist.
      #
      # @example
      #   valkey.msetnx("key1", "v1", "key2", "v2")
      #     # => true
      #
      # @param [Array<String>] args array of keys and values
      # @return [Boolean] whether or not all values were set
      #
      # @see #mapped_msetnx
      def msetnx(*args)
        send_command(RequestType::MSET_NX, args)
      end

      # Set one or more values, only if none of the keys exist.
      #
      # @example
      #   valkey.mapped_msetnx({ "key1" => "v1", "key2" => "v2" })
      #     # => true
      #
      # @param [Hash] hash keys mapping to values
      # @return [Boolean] whether or not all values were set
      #
      # @see #msetnx
      def mapped_msetnx(hash)
        msetnx(*hash.flatten)
      end

      # Get the value of a key.
      #
      # @param [String] key
      # @return [String]
      def get(key)
        send_command(RequestType::GET, [key])
      end

      # Get the values of all the given keys.
      #
      # @example
      #   valkey.mget("key1", "key2")
      #     # => ["v1", "v2"]
      #
      # @param [Array<String>] keys
      # @return [Array<String>] an array of values for the specified keys
      #
      # @see #mapped_mget
      def mget(*keys, &blk)
        keys.flatten!(1)
        send_command(RequestType::MGET, keys, &blk)
      end

      # Get the values of all the given keys.
      #
      # @example
      #   valkey.mapped_mget("key1", "key2")
      #     # => { "key1" => "v1", "key2" => "v2" }
      #
      # @param [Array<String>] keys array of keys
      # @return [Hash] a hash mapping the specified keys to their values
      #
      # @see #mget
      def mapped_mget(*keys)
        mget(*keys) do |reply|
          if reply.is_a?(Array)
            Hash[keys.zip(reply)]
          else
            reply
          end
        end
      end

      # Overwrite part of a string at key starting at the specified offset.
      #
      # @param [String] key
      # @param [Integer] offset byte offset
      # @param [String] value
      # @return [Integer] length of the string after it was modified
      def setrange(key, offset, value)
        send_command(RequestType::SET_RANGE, [key, offset, value])
      end

      # Get a substring of the string stored at a key.
      #
      # @param [String] key
      # @param [Integer] start zero-based start offset
      # @param [Integer] stop zero-based end offset. Use -1 for representing
      #   the end of the string
      # @return [Integer] `0` or `1`
      def getrange(key, start, stop)
        send_command(RequestType::GET_RANGE, [key, start, stop])
      end

      # Append a value to a key.
      #
      # @param [String] key
      # @param [String] value value to append
      # @return [Integer] length of the string after appending
      def append(key, value)
        send_command(RequestType::APPEND, [key, value])
      end

      # Set the string value of a key and return its old value.
      #
      # @param [String] key
      # @param [String] value value to replace the current value with
      # @return [String] the old value stored in the key, or `nil` if the key
      #   did not exist
      def getset(key, value)
        send_command(RequestType::GET_SET, [key, value])
      end

      # Get the value of key and delete the key. This command is similar to GET,
      # except for the fact that it also deletes the key on success.
      #
      # @param [String] key
      # @return [String] the old value stored in the key, or `nil` if the key
      #   did not exist
      def getdel(key)
        send_command(RequestType::GET_DEL, [key])
      end

      # Get the value of key and optionally set its expiration. GETEX is similar to
      # GET, but is a write command with additional options. When no options are
      # provided, GETEX behaves like GET.
      #
      # @param [String] key
      # @param [Hash] options
      #   - `:ex => Integer`: Set the specified expire time, in seconds.
      #   - `:px => Integer`: Set the specified expire time, in milliseconds.
      #   - `:exat => true`: Set the specified Unix time at which the key will
      #      expire, in seconds.
      #   - `:pxat => true`: Set the specified Unix time at which the key will
      #      expire, in milliseconds.
      #   - `:persist => true`: Remove the time to live associated with the key.
      # @return [String] The value of key, or nil when key does not exist.
      def getex(key, ex: nil, px: nil, exat: nil, pxat: nil, persist: false)
        args = [key]
        args << "EX" << ex if ex
        args << "PX" << px if px
        args << "EXAT" << exat if exat
        args << "PXAT" << pxat if pxat
        args << "PERSIST" if persist

        send_command(RequestType::GET_EX, args)
      end

      # Get the length of the value stored in a key.
      #
      # @param [String] key
      # @return [Integer] the length of the value stored in the key, or 0
      #   if the key does not exist
      def strlen(key)
        send_command(RequestType::STRLEN, [key])
      end
    end
  end
end
