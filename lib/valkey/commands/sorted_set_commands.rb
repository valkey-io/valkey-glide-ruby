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

      # Removes and returns up to count members with the highest scores in the sorted set stored at key.
      #
      # @example Popping a member
      #   valkey.zpopmax('zset')
      #   #=> ['b', 2.0]
      # @example With count option
      #   valkey.zpopmax('zset', 2)
      #   #=> [['b', 2.0], ['a', 1.0]]
      #
      # @params key [String] a key of the sorted set
      # @params count [Integer] a number of members
      #
      # @return [Array<String, Float>] element and score pair if count is not specified
      # @return [Array<Array<String, Float>>] list of popped elements and scores
      def zpopmax(key, count = nil)
        command_args = [key]
        command_args << Integer(count) if count
        send_command(RequestType::Z_POP_MAX, command_args) do |members|
          members = Utils::FloatifyPairs.call(members)
          count.to_i > 1 ? members : members.first
        end
      end

      # Removes and returns up to count members with the lowest scores in the sorted set stored at key.
      #
      # @example Popping a member
      #   valkey.zpopmin('zset')
      #   #=> ['a', 1.0]
      # @example With count option
      #   valkey.zpopmin('zset', 2)
      #   #=> [['a', 1.0], ['b', 2.0]]
      #
      # @params key [String] a key of the sorted set
      # @params count [Integer] a number of members
      #
      # @return [Array<String, Float>] element and score pair if count is not specified
      # @return [Array<Array<String, Float>>] list of popped elements and scores
      def zpopmin(key, count = nil)
        command_args = [key]
        command_args << Integer(count) if count
        send_command(RequestType::Z_POP_MIN, command_args) do |members|
          members = Utils::FloatifyPairs.call(members)
          count.to_i > 1 ? members : members.first
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

      # Get the scores associated with the given members in a sorted set.
      #
      # @example Get the scores for members "a" and "b"
      #   valkey.zmscore("zset", "a", "b")
      #     # => [32.0, 48.0]
      #
      # @param [String] key
      # @param [String, Array<String>] members
      # @return [Array<Float>] scores of the members
      def zmscore(key, *members)
        send_command(RequestType::Z_MSCORE, [key, *members]) do |reply|
          reply.map(&Utils::Floatify)
        end
      end

      # Return a range of members in a sorted set, by index, score or lexicographical ordering.
      #
      # @example Retrieve all members from a sorted set, by index
      #   valkey.zrange("zset", 0, -1)
      #     # => ["a", "b"]
      # @example Retrieve all members and their scores from a sorted set
      #   valkey.zrange("zset", 0, -1, :with_scores => true)
      #     # => [["a", 32.0], ["b", 64.0]]
      #
      # @param [String] key
      # @param [Integer] start start index
      # @param [Integer] stop stop index
      # @param [Hash] options
      #   - `:by_score => false`: return members by score
      #   - `:by_lex => false`: return members by lexicographical ordering
      #   - `:rev => false`: reverse the ordering, from highest to lowest
      #   - `:limit => [offset, count]`: skip `offset` members, return a maximum of
      #   `count` members
      #   - `:with_scores => true`: include scores in output
      #
      # @return [Array<String>, Array<[String, Float]>]
      #   - when `:with_scores` is not specified, an array of members
      #   - when `:with_scores` is specified, an array with `[member, score]` pairs
      def zrange(key, start, stop, byscore: false, by_score: byscore, bylex: false, by_lex: bylex,
                 rev: false, limit: nil, withscores: false, with_scores: withscores)
        raise ArgumentError, "only one of :by_score or :by_lex can be specified" if by_score && by_lex

        args = [key, start, stop]

        if by_score
          args << "BYSCORE"
        elsif by_lex
          args << "BYLEX"
        end

        args << "REV" if rev

        if limit
          args << "LIMIT"
          args.concat(limit.map { |l| Integer(l) })
        end

        if with_scores
          args << "WITHSCORES"
          block = Utils::FloatifyPairs
        end

        send_command(RequestType::Z_RANGE, args, &block)
      end

      # Select a range of members in a sorted set, by index, score or lexicographical ordering
      # and store the resulting sorted set in a new key.
      #
      # @example
      #   valkey.zadd("foo", [[1.0, "s1"], [2.0, "s2"], [3.0, "s3"]])
      #   valkey.zrangestore("bar", "foo", 0, 1)
      #     # => 2
      #   valkey.zrange("bar", 0, -1)
      #     # => ["s1", "s2"]
      #
      # @return [Integer] the number of elements in the resulting sorted set
      # @see #zrange
      def zrangestore(dest_key, src_key, start, stop, byscore: false, by_score: byscore,
                      bylex: false, by_lex: bylex, rev: false, limit: nil)
        raise ArgumentError, "only one of :by_score or :by_lex can be specified" if by_score && by_lex

        args = [dest_key, src_key, start, stop]

        if by_score
          args << "BYSCORE"
        elsif by_lex
          args << "BYLEX"
        end

        args << "REV" if rev

        if limit
          args << "LIMIT"
          args.concat(limit.map { |l| Integer(l) })
        end

        send_command(RequestType::Z_RANGE_STORE, args)
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

      # Remove all members in a sorted set within the given indexes.
      #
      # @example Remove first 5 members
      #   valkey.zremrangebyrank("zset", 0, 4)
      #     # => 5
      # @example Remove last 5 members
      #   valkey.zremrangebyrank("zset", -5, -1)
      #     # => 5
      #
      # @param [String] key
      # @param [Integer] start start index
      # @param [Integer] stop stop index
      # @return [Integer] number of members that were removed
      def zremrangebyrank(key, start, stop)
        send_command(RequestType::Z_REM_RANGE_BY_RANK, [key, start, stop])
      end

      # Count the members, with the same score in a sorted set, within the given lexicographical range.
      #
      # @example Count members matching a
      #   valkey.zlexcount("zset", "[a", "[a\xff")
      #     # => 1
      # @example Count members matching a-z
      #   valkey.zlexcount("zset", "[a", "[z\xff")
      #     # => 26
      #
      # @param [String] key
      # @param [String] min
      #   - inclusive minimum is specified by prefixing `(`
      #   - exclusive minimum is specified by prefixing `[`
      # @param [String] max
      #   - inclusive maximum is specified by prefixing `(`
      #   - exclusive maximum is specified by prefixing `[`
      #
      # @return [Integer] number of members within the specified lexicographical range
      def zlexcount(key, min, max)
        send_command(RequestType::Z_LEX_COUNT, [key, min, max])
      end

      # Remove all members in a sorted set within the given scores.
      #
      # @example Remove members with score `>= 5` and `< 100`
      #   valkey.zremrangebyscore("zset", "5", "(100")
      #     # => 2
      # @example Remove members with scores `> 5`
      #   valkey.zremrangebyscore("zset", "(5", "+inf")
      #     # => 2
      #
      # @param [String] key
      # @param [String] min
      #   - inclusive minimum score is specified verbatim
      #   - exclusive minimum score is specified by prefixing `(`
      # @param [String] max
      #   - inclusive maximum score is specified verbatim
      #   - exclusive maximum score is specified by prefixing `(`
      # @return [Integer] number of members that were removed
      def zremrangebyscore(key, min, max)
        send_command(RequestType::Z_REM_RANGE_BY_SCORE, [key, min, max])
      end

      # Count the members in a sorted set with scores within the given values.
      #
      # @example Count members with score `>= 5` and `< 100`
      #   valkey.zcount("zset", "5", "(100")
      #     # => 2
      # @example Count members with scores `> 5`
      #   valkey.zcount("zset", "(5", "+inf")
      #     # => 2
      #
      # @param [String] key
      # @param [String] min
      #   - inclusive minimum score is specified verbatim
      #   - exclusive minimum score is specified by prefixing `(`
      # @param [String] max
      #   - inclusive maximum score is specified verbatim
      #   - exclusive maximum score is specified by prefixing `(`
      # @return [Integer] number of members in within the specified range
      def zcount(key, min, max)
        send_command(RequestType::Z_COUNT, [key, min, max])
      end

      # Return the intersection of multiple sorted sets
      #
      # @example Retrieve the intersection of `2*zsetA` and `1*zsetB`
      #   valkey.zinter("zsetA", "zsetB", :weights => [2.0, 1.0])
      #     # => ["v1", "v2"]
      # @example Retrieve the intersection of `2*zsetA` and `1*zsetB`, and their scores
      #   valkey.zinter("zsetA", "zsetB", :weights => [2.0, 1.0], :with_scores => true)
      #     # => [["v1", 3.0], ["v2", 6.0]]
      #
      # @param [String, Array<String>] keys one or more keys to intersect
      # @param [Hash] options
      #   - `:weights => [Float, Float, ...]`: weights to associate with source
      #   sorted sets
      #   - `:aggregate => String`: aggregate function to use (sum, min, max, ...)
      #   - `:with_scores => true`: include scores in output
      #
      # @return [Array<String>, Array<[String, Float]>]
      #   - when `:with_scores` is not specified, an array of members
      #   - when `:with_scores` is specified, an array with `[member, score]` pairs
      def zinter(*args)
        _zsets_operation(RequestType::Z_INTER, *args)
      end
      ruby2_keywords(:zinter) if respond_to?(:ruby2_keywords, true)

      # Intersect multiple sorted sets and store the resulting sorted set in a new
      # key.
      #
      # @example Compute the intersection of `2*zsetA` with `1*zsetB`, summing their scores
      #   valkey.zinterstore("zsetC", ["zsetA", "zsetB"], :weights => [2.0, 1.0], :aggregate => "sum")
      #     # => 4
      #
      # @param [String] destination destination key
      # @param [Array<String>] keys source keys
      # @param [Hash] options
      #   - `:weights => [Array<Float>]`: weights to associate with source
      #   sorted sets
      #   - `:aggregate => String`: aggregate function to use (sum, min, max)
      # @return [Integer] number of elements in the resulting sorted set
      def zinterstore(*args)
        _zsets_operation_store(RequestType::Z_INTER_STORE, *args)
      end
      ruby2_keywords(:zinterstore) if respond_to?(:ruby2_keywords, true)

      # Return the union of multiple sorted sets
      #
      # @example Retrieve the union of `2*zsetA` and `1*zsetB`
      #   valkey.zunion("zsetA", "zsetB", :weights => [2.0, 1.0])
      #     # => ["v1", "v2"]
      # @example Retrieve the union of `2*zsetA` and `1*zsetB`, and their scores
      #   valkey.zunion("zsetA", "zsetB", :weights => [2.0, 1.0], :with_scores => true)
      #     # => [["v1", 3.0], ["v2", 6.0]]
      #
      # @param [String, Array<String>] keys one or more keys to union
      # @param [Hash] options
      #   - `:weights => [Array<Float>]`: weights to associate with source
      #   sorted sets
      #   - `:aggregate => String`: aggregate function to use (sum, min, max)
      #   - `:with_scores => true`: include scores in output
      #
      # @return [Array<String>, Array<[String, Float]>]
      #   - when `:with_scores` is not specified, an array of members
      #   - when `:with_scores` is specified, an array with `[member, score]` pairs
      def zunion(*args)
        _zsets_operation(RequestType::Z_UNION, *args)
      end
      ruby2_keywords(:zunion) if respond_to?(:ruby2_keywords, true)

      # Add multiple sorted sets and store the resulting sorted set in a new key.
      #
      # @example Compute the union of `2*zsetA` with `1*zsetB`, summing their scores
      #   valkey.zunionstore("zsetC", ["zsetA", "zsetB"], :weights => [2.0, 1.0], :aggregate => "sum")
      #     # => 8
      #
      # @param [String] destination destination key
      # @param [Array<String>] keys source keys
      # @param [Hash] options
      #   - `:weights => [Float, Float, ...]`: weights to associate with source
      #   sorted sets
      #   - `:aggregate => String`: aggregate function to use (sum, min, max, ...)
      # @return [Integer] number of elements in the resulting sorted set
      def zunionstore(*args)
        _zsets_operation_store(RequestType::Z_UNION_STORE, *args)
      end
      ruby2_keywords(:zunionstore) if respond_to?(:ruby2_keywords, true)

      # Return the difference between the first and all successive input sorted sets
      #
      # @example
      #   valkey.zadd("zsetA", [[1.0, "v1"], [2.0, "v2"]])
      #   valkey.zadd("zsetB", [[3.0, "v2"], [2.0, "v3"]])
      #   valkey.zdiff("zsetA", "zsetB")
      #     => ["v1"]
      # @example With scores
      #   valkey.zadd("zsetA", [[1.0, "v1"], [2.0, "v2"]])
      #   valkey.zadd("zsetB", [[3.0, "v2"], [2.0, "v3"]])
      #   valkey.zdiff("zsetA", "zsetB", :with_scores => true)
      #     => [["v1", 1.0]]
      #
      # @param [String, Array<String>] keys one or more keys to compute the difference
      # @param [Hash] options
      #   - `:with_scores => true`: include scores in output
      #
      # @return [Array<String>, Array<[String, Float]>]
      #   - when `:with_scores` is not specified, an array of members
      #   - when `:with_scores` is specified, an array with `[member, score]` pairs
      def zdiff(*keys, with_scores: false)
        _zsets_operation(RequestType::Z_DIFF, *keys, with_scores: with_scores)
      end

      # Compute the difference between the first and all successive input sorted sets
      # and store the resulting sorted set in a new key
      #
      # @example
      #   valkey.zadd("zsetA", [[1.0, "v1"], [2.0, "v2"]])
      #   valkey.zadd("zsetB", [[3.0, "v2"], [2.0, "v3"]])
      #   valkey.zdiffstore("zsetA", "zsetB")
      #     # => 1
      #
      # @param [String] destination destination key
      # @param [Array<String>] keys source keys
      # @return [Integer] number of elements in the resulting sorted set
      def zdiffstore(*args)
        _zsets_operation_store(RequestType::Z_DIFF_STORE, *args)
      end
      ruby2_keywords(:zdiffstore) if respond_to?(:ruby2_keywords, true)

      # Scan a sorted set
      #
      # @example Retrieve the first batch of key/value pairs in a hash
      #   valkey.zscan("zset", 0)
      #
      # @param [String, Integer] cursor the cursor of the iteration
      # @param [Hash] options
      #   - `:match => String`: only return keys matching the pattern
      #   - `:count => Integer`: return count keys at most per iteration
      #
      # @return [String, Array<[String, Float]>] the next cursor and all found
      #   members and scores
      #
      # See the [Valkey Server ZSCAN documentation](https://valkey.io/docs/latest/commands/zscan/) for further details
      def zscan(key, cursor, **options)
        _scan(RequestType::Z_SCAN, cursor, [key], **options) do |reply|
          [reply[0], Utils::FloatifyPairs.call(reply[1])]
        end
      end

      private

      def _zsets_operation(cmd, *keys, weights: nil, aggregate: nil, with_scores: false)
        keys.flatten!(1)
        command_args = [keys.size].concat(keys)

        if weights
          command_args << "WEIGHTS"
          command_args.concat(weights)
        end

        command_args << "AGGREGATE" << aggregate if aggregate

        if with_scores
          command_args << "WITHSCORES"
          block = Utils::FloatifyPairs
        end

        send_command(cmd, command_args, &block)
      end

      def _zsets_operation_store(cmd, destination, keys, weights: nil, aggregate: nil)
        keys.flatten!(1)
        command_args = [destination, keys.size].concat(keys)

        if weights
          command_args << "WEIGHTS"
          command_args.concat(weights)
        end

        command_args << "AGGREGATE" << aggregate if aggregate

        send_command(cmd, command_args)
      end
    end
  end
end
