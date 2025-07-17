# frozen_string_literal: true

class Valkey
  module Commands
    module SortedSetCommands
      # Get the number of members in a sorted set.
      #
      # @example
      #   valkey.zcard("zset")
      #     # => 4
      #
      # @param [String] key
      # @return [Integer]
      def zcard(key)
        send_command(RequestType::Z_CARD, [key])
      end

      # Add one or more members to a sorted set, or update the score for members
      # that already exist.
      #
      # @example Add a single `[score, member]` pair to a sorted set
      #   valkey.zadd("zset", 32.0, "member")
      # @example Add an array of `[score, member]` pairs to a sorted set
      #   valkey.zadd("zset", [[32.0, "a"], [64.0, "b"]])
      #
      # @param [String] key
      # @param [[Float, String], Array<[Float, String]>] args
      #   - a single `[score, member]` pair
      #   - an array of `[score, member]` pairs
      # @param [Hash] options
      #   - `:xx => true`: Only update elements that already exist (never
      #   add elements)
      #   - `:nx => true`: Don't update already existing elements (always
      #   add new elements)
      #   - `:lt => true`: Only update existing elements if the new score
      #   is less than the current score
      #   - `:gt => true`: Only update existing elements if the new score
      #   is greater than the current score
      #   - `:ch => true`: Modify the return value from the number of new
      #   elements added, to the total number of elements changed (CH is an
      #   abbreviation of changed); changed elements are new elements added
      #   and elements already existing for which the score was updated
      #   - `:incr => true`: When this option is specified ZADD acts like
      #   ZINCRBY; only one score-element pair can be specified in this mode
      #
      # @return [Boolean, Integer, Float]
      #   - `Boolean` when a single pair is specified, holding whether or not it was
      #   **added** to the sorted set.
      #   - `Integer` when an array of pairs is specified, holding the number of
      #   pairs that were **added** to the sorted set.
      #   - `Float` when option :incr is specified, holding the score of the member
      #   after incrementing it.
      def zadd(key, *args, nx: nil, xx: nil, lt: nil, gt: nil, ch: nil, incr: nil)
        command_args = [key]
        command_args << "NX" if nx
        command_args << "XX" if xx
        command_args << "LT" if lt
        command_args << "GT" if gt
        command_args << "CH" if ch
        command_args << "INCR" if incr

        if args.size == 1 && args[0].is_a?(Array)
          members_to_add = args[0]
          return 0 if members_to_add.empty?

          # Variadic: return float if INCR, integer if !INCR
          send_command(RequestType::Z_ADD, command_args + members_to_add.flatten, &(incr ? Utils::Floatify : nil))
        elsif args.size == 2
          # Single pair: return float if INCR, boolean if !INCR
          send_command(RequestType::Z_ADD, command_args + args.flatten.flatten, &(incr ? Utils::Floatify : Utils::Boolify))
        else
          raise ArgumentError, "wrong number of arguments"
        end
      end

      # Increment the score of a member in a sorted set.
      #
      # @example
      #   valkey.zincrby("zset", 32.0, "a")
      #     # => 64.0
      #
      # @param [String] key
      # @param [Float] increment
      # @param [String] member
      # @return [Float] score of the member after incrementing it
      def zincrby(key, increment, member)
        send_command(RequestType::Z_INCR_BY, [key, increment, member], &Utils::Floatify)
      end

      # Remove one or more members from a sorted set.
      #
      # @example Remove a single member from a sorted set
      #   valkey.zrem("zset", "a")
      # @example Remove an array of members from a sorted set
      #   valkey.zrem("zset", ["a", "b"])
      #
      # @param [String] key
      # @param [String, Array<String>] member
      #   - a single member
      #   - an array of members
      #
      # @return [Boolean, Integer]
      #   - `Boolean` when a single member is specified, holding whether or not it
      #   was removed from the sorted set
      #   - `Integer` when an array of pairs is specified, holding the number of
      #   members that were removed to the sorted set
      def zrem(key, member)
        if member.is_a?(Array)
          members_to_remove = member
          return 0 if members_to_remove.empty?
        end
        send_command(RequestType::Z_REM, [key, member].flatten) do |reply|
          if member.is_a? Array
            # Variadic: return integer
            reply
          else
            # Single argument: return boolean
            Utils::Boolify.call(reply)
          end
        end
      end

      # Get the score associated with the given member in a sorted set.
      #
      # @example Get the score for member "a"
      #   valkey.zscore("zset", "a")
      #     # => 32.0
      #
      # @param [String] key
      # @param [String] member
      # @return [Float] score of the member
      def zscore(key, member)
        send_command(RequestType::Z_SCORE, [key, member], &Utils::Floatify)
      end

      # Determine the index of a member in a sorted set.
      #
      # @example Retrieve member rank
      #   valkey.zrank("zset", "a")
      #     # => 3
      # @example Retrieve member rank with their score
      #   valkey.zrank("zset", "a", :with_score => true)
      #     # => [3, 32.0]
      #
      # @param [String] key
      # @param [String] member
      #
      # @return [Integer, [Integer, Float]]
      #   - when `:with_score` is not specified, an Integer
      #   - when `:with_score` is specified, a `[rank, score]` pair
      def zrank(key, member, withscore: false, with_score: withscore)
        args = [key, member]

        if with_score
          args << "WITHSCORE"
          block = Utils::FloatifyPair
        end

        send_command(RequestType::Z_RANK, args, &block)
      end

      # Determine the index of a member in a sorted set, with scores ordered from
      # high to low.
      #
      # @example Retrieve member rank
      #   valkey.zrevrank("zset", "a")
      #     # => 3
      # @example Retrieve member rank with their score
      #   valkey.zrevrank("zset", "a", :with_score => true)
      #     # => [3, 32.0]
      #
      # @param [String] key
      # @param [String] member
      #
      # @return [Integer, [Integer, Float]]
      #   - when `:with_score` is not specified, an Integer
      #   - when `:with_score` is specified, a `[rank, score]` pair
      def zrevrank(key, member, withscore: false, with_score: withscore)
        args = [key, member]

        if with_score
          args << "WITHSCORE"
          block = Utils::FloatifyPair
        end

        send_command(RequestType::Z_REV_RANK, args, &block)
      end
    end
  end
end
