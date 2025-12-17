# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands related to RedisJSON / Valkey JSON.
    #
    # @see https://redis.io/docs/stack/json/
    #
    module JsonCommands
      # Get JSON value at path.
      #
      # @example Get entire JSON document
      #   valkey.json_get("user:1")
      #     # => "{\"name\":\"John\",\"age\":30}"
      # @example Get specific path
      #   valkey.json_get("user:1", "$.name")
      #     # => "[\"John\"]"
      #
      # @param [String] key the key
      # @param [Array<String>] paths optional paths to retrieve
      # @return [String, nil] JSON string or nil if key doesn't exist
      #
      # @see https://redis.io/commands/json.get/
      def json_get(key, *paths)
        args = [key] + paths
        send_command(RequestType::JSON_GET, args)
      end

      # Set JSON value at path.
      #
      # @example Set entire document
      #   valkey.json_set("user:1", "$", '{"name":"John","age":30}')
      #     # => "OK"
      # @example Set specific path
      #   valkey.json_set("user:1", "$.age", "31")
      #     # => "OK"
      #
      # @param [String] key the key
      # @param [String] path the JSON path
      # @param [String] value the JSON value
      # @return [String] "OK"
      #
      # @see https://redis.io/commands/json.set/
      def json_set(key, path, value)
        send_command(RequestType::JSON_SET, [key, path, value])
      end

      # Delete JSON value at path.
      #
      # @example Delete entire document
      #   valkey.json_del("user:1")
      #     # => 1
      # @example Delete specific path
      #   valkey.json_del("user:1", "$.age")
      #     # => 1
      #
      # @param [String] key the key
      # @param [String] path optional path (default: root)
      # @return [Integer] number of paths deleted
      #
      # @see https://redis.io/commands/json.del/
      def json_del(key, path = nil)
        args = [key]
        args << path if path
        send_command(RequestType::JSON_DEL, args)
      end

      # Alias for json_del (deprecated).
      #
      # @param [String] key the key
      # @param [String] path optional path
      # @return [Integer] number of paths deleted
      #
      # @see https://redis.io/commands/json.forget/
      def json_forget(key, path = nil)
        args = [key]
        args << path if path
        send_command(RequestType::JSON_FORGET, args)
      end

      # Get multiple JSON values.
      #
      # @example Get from multiple keys
      #   valkey.json_mget("user:1", "user:2", "$.name")
      #     # => ["[\"John\"]", "[\"Jane\"]"]
      #
      # @param [Array<String>] keys_and_path keys followed by path
      # @return [Array<String, nil>] array of JSON strings
      #
      # @see https://redis.io/commands/json.mget/
      def json_mget(*keys_and_path)
        send_command(RequestType::JSON_MGET, keys_and_path)
      end

      # Get the type of JSON value at path.
      #
      # @example Get type
      #   valkey.json_type("user:1", "$.age")
      #     # => ["integer"]
      #
      # @param [String] key the key
      # @param [String] path optional path
      # @return [Array<String>] array of type names
      #
      # @see https://redis.io/commands/json.type/
      def json_type(key, path = nil)
        args = [key]
        args << path if path
        send_command(RequestType::JSON_TYPE, args)
      end

      # Increment number at path.
      #
      # @example Increment age
      #   valkey.json_numincrby("user:1", "$.age", 1)
      #     # => "[31]"
      #
      # @param [String] key the key
      # @param [String] path the JSON path
      # @param [Numeric] value the increment value
      # @return [String] JSON array of new values
      #
      # @see https://redis.io/commands/json.numincrby/
      def json_numincrby(key, path, value)
        send_command(RequestType::JSON_NUM_INCR_BY, [key, path, value.to_s])
      end

      # Multiply number at path.
      #
      # @example Multiply price
      #   valkey.json_nummultby("product:1", "$.price", 1.1)
      #     # => "[110.0]"
      #
      # @param [String] key the key
      # @param [String] path the JSON path
      # @param [Numeric] value the multiplier
      # @return [String] JSON array of new values
      #
      # @see https://redis.io/commands/json.nummultby/
      def json_nummultby(key, path, value)
        send_command(RequestType::JSON_NUM_MULT_BY, [key, path, value.to_s])
      end

      # Append string to JSON string at path.
      #
      # @example Append to name
      #   valkey.json_strappend("user:1", "$.name", '" Jr."')
      #     # => [8]
      #
      # @param [String] key the key
      # @param [String] path the JSON path
      # @param [String] value the string to append
      # @return [Array<Integer>] array of new string lengths
      #
      # @see https://redis.io/commands/json.strappend/
      def json_strappend(key, path, value)
        send_command(RequestType::JSON_STR_APPEND, [key, path, value])
      end

      # Get length of JSON string at path.
      #
      # @example Get string length
      #   valkey.json_strlen("user:1", "$.name")
      #     # => [4]
      #
      # @param [String] key the key
      # @param [String] path optional path
      # @return [Array<Integer, nil>] array of string lengths
      #
      # @see https://redis.io/commands/json.strlen/
      def json_strlen(key, path = nil)
        args = [key]
        args << path if path
        send_command(RequestType::JSON_STR_LEN, args)
      end

      # Append values to JSON array at path.
      #
      # @example Append to array
      #   valkey.json_arrappend("user:1", "$.tags", '"ruby"', '"valkey"')
      #     # => [3]
      #
      # @param [String] key the key
      # @param [String] path the JSON path
      # @param [Array<String>] values JSON values to append
      # @return [Array<Integer>] array of new array lengths
      #
      # @see https://redis.io/commands/json.arrappend/
      def json_arrappend(key, path, *values)
        send_command(RequestType::JSON_ARR_APPEND, [key, path] + values)
      end

      # Get index of value in JSON array.
      #
      # @example Find index
      #   valkey.json_arrindex("user:1", "$.tags", '"ruby"')
      #     # => [0]
      #
      # @param [String] key the key
      # @param [String] path the JSON path
      # @param [String] value the value to search for
      # @param [Integer] start optional start index
      # @param [Integer] stop optional stop index
      # @return [Array<Integer>] array of indices (-1 if not found)
      #
      # @see https://redis.io/commands/json.arrindex/
      def json_arrindex(key, path, value, start = nil, stop = nil)
        args = [key, path, value]
        args << start.to_s if start
        args << stop.to_s if stop
        send_command(RequestType::JSON_ARR_INDEX, args)
      end

      # Insert values into JSON array at index.
      #
      # @example Insert at index
      #   valkey.json_arrinsert("user:1", "$.tags", 1, '"python"')
      #     # => [3]
      #
      # @param [String] key the key
      # @param [String] path the JSON path
      # @param [Integer] index the index to insert at
      # @param [Array<String>] values JSON values to insert
      # @return [Array<Integer>] array of new array lengths
      #
      # @see https://redis.io/commands/json.arrinsert/
      def json_arrinsert(key, path, index, *values)
        send_command(RequestType::JSON_ARR_INSERT, [key, path, index.to_s] + values)
      end

      # Get length of JSON array at path.
      #
      # @example Get array length
      #   valkey.json_arrlen("user:1", "$.tags")
      #     # => [2]
      #
      # @param [String] key the key
      # @param [String] path optional path
      # @return [Array<Integer, nil>] array of array lengths
      #
      # @see https://redis.io/commands/json.arrlen/
      def json_arrlen(key, path = nil)
        args = [key]
        args << path if path
        send_command(RequestType::JSON_ARR_LEN, args)
      end

      # Pop element from JSON array.
      #
      # @example Pop last element
      #   valkey.json_arrpop("user:1", "$.tags")
      #     # => ["\"ruby\""]
      # @example Pop at index
      #   valkey.json_arrpop("user:1", "$.tags", 0)
      #     # => ["\"python\""]
      #
      # @param [String] key the key
      # @param [String] path optional path
      # @param [Integer] index optional index (default: -1)
      # @return [Array<String, nil>] array of popped values
      #
      # @see https://redis.io/commands/json.arrpop/
      def json_arrpop(key, path = nil, index = nil)
        args = [key]
        args << path if path
        args << index.to_s if index
        send_command(RequestType::JSON_ARR_POP, args)
      end

      # Trim JSON array to specified range.
      #
      # @example Trim array
      #   valkey.json_arrtrim("user:1", "$.tags", 0, 1)
      #     # => [2]
      #
      # @param [String] key the key
      # @param [String] path the JSON path
      # @param [Integer] start start index
      # @param [Integer] stop stop index
      # @return [Array<Integer>] array of new array lengths
      #
      # @see https://redis.io/commands/json.arrtrim/
      def json_arrtrim(key, path, start, stop)
        send_command(RequestType::JSON_ARR_TRIM, [key, path, start.to_s, stop.to_s])
      end

      # Get keys of JSON object at path.
      #
      # @example Get object keys
      #   valkey.json_objkeys("user:1", "$")
      #     # => [["name", "age"]]
      #
      # @param [String] key the key
      # @param [String] path optional path
      # @return [Array<Array<String>>] array of key arrays
      #
      # @see https://redis.io/commands/json.objkeys/
      def json_objkeys(key, path = nil)
        args = [key]
        args << path if path
        send_command(RequestType::JSON_OBJ_KEYS, args)
      end

      # Get number of keys in JSON object at path.
      #
      # @example Get object length
      #   valkey.json_objlen("user:1", "$")
      #     # => [2]
      #
      # @param [String] key the key
      # @param [String] path optional path
      # @return [Array<Integer, nil>] array of key counts
      #
      # @see https://redis.io/commands/json.objlen/
      def json_objlen(key, path = nil)
        args = [key]
        args << path if path
        send_command(RequestType::JSON_OBJ_LEN, args)
      end

      # Clear container values at path.
      #
      # @example Clear array
      #   valkey.json_clear("user:1", "$.tags")
      #     # => 1
      #
      # @param [String] key the key
      # @param [String] path optional path
      # @return [Integer] number of paths cleared
      #
      # @see https://redis.io/commands/json.clear/
      def json_clear(key, path = nil)
        args = [key]
        args << path if path
        send_command(RequestType::JSON_CLEAR, args)
      end

      # Toggle boolean value at path.
      #
      # @example Toggle boolean
      #   valkey.json_toggle("user:1", "$.active")
      #     # => [1]
      #
      # @param [String] key the key
      # @param [String] path the JSON path
      # @return [Array<Integer>] array of new boolean values (0 or 1)
      #
      # @see https://redis.io/commands/json.toggle/
      def json_toggle(key, path)
        send_command(RequestType::JSON_TOGGLE, [key, path])
      end

      # Get debug information about JSON value.
      #
      # @example Get memory usage
      #   valkey.json_debug("MEMORY", "user:1", "$")
      #     # => [120]
      #
      # @param [String] subcommand the debug subcommand
      # @param [String] key the key
      # @param [String] path optional path
      # @return [Object] depends on subcommand
      #
      # @see https://redis.io/commands/json.debug/
      def json_debug(subcommand, key, path = nil)
        args = [subcommand, key]
        args << path if path
        send_command(RequestType::JSON_DEBUG, args)
      end

      # Get JSON value in RESP format.
      #
      # @example Get as RESP
      #   valkey.json_resp("user:1", "$")
      #     # => [["name", "John"], ["age", 30]]
      #
      # @param [String] key the key
      # @param [String] path optional path
      # @return [Object] RESP representation
      #
      # @see https://redis.io/commands/json.resp/
      def json_resp(key, path = nil)
        args = [key]
        args << path if path
        send_command(RequestType::JSON_RESP, args)
      end
    end
  end
end
