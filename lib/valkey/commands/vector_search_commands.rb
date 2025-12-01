# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands for vector search operations using RediSearch.
    #
    # @see https://redis.io/docs/stack/search/ RediSearch Documentation
    #
    module VectorSearchCommands
      # List all indexes.
      #
      # @example
      #   valkey.ft_list
      #     # => ["idx1", "idx2"]
      #
      # @return [Array<String>] array of index names
      #
      # @see https://redis.io/commands/ft-list/
      def ft_list
        send_command(RequestType::FT_LIST)
      end

      # Execute an aggregation query on an index.
      #
      # @example Simple aggregation
      #   valkey.ft_aggregate("idx", "*")
      # @example Aggregation with group by
      #   valkey.ft_aggregate("idx", "*", "GROUPBY", "1", "@field", "REDUCE", "COUNT", "0")
      #
      # @param [String] index the index name
      # @param [String] query the query string
      # @param [Array<String>] args additional aggregation arguments (GROUPBY, REDUCE, SORTBY, etc.)
      # @return [Array] aggregation results
      #
      # @see https://redis.io/commands/ft-aggregate/
      def ft_aggregate(index, query, *args)
        send_command(RequestType::FT_AGGREGATE, [index, query, *args])
      end

      # Add an alias to an index.
      #
      # @example
      #   valkey.ft_alias_add("myalias", "idx1")
      #     # => "OK"
      #
      # @param [String] alias_name the alias name
      # @param [String] index the index name
      # @return [String] "OK"
      #
      # @see https://redis.io/commands/ft-alias-add/
      def ft_alias_add(alias_name, index)
        send_command(RequestType::FT_ALIAS_ADD, [alias_name, index])
      end

      # Delete an alias from an index.
      #
      # @example
      #   valkey.ft_alias_del("myalias")
      #     # => "OK"
      #
      # @param [String] alias_name the alias name
      # @return [String] "OK"
      #
      # @see https://redis.io/commands/ft-alias-del/
      def ft_alias_del(alias_name)
        send_command(RequestType::FT_ALIAS_DEL, [alias_name])
      end

      # List all aliases.
      #
      # @example
      #   valkey.ft_alias_list
      #     # => ["alias1", "alias2"]
      #
      # @return [Array<String>] array of alias names
      #
      # @see https://redis.io/commands/ft-alias-list/
      def ft_alias_list
        send_command(RequestType::FT_ALIAS_LIST)
      end

      # Update an alias to point to a different index.
      #
      # @example
      #   valkey.ft_alias_update("myalias", "idx2")
      #     # => "OK"
      #
      # @param [String] alias_name the alias name
      # @param [String] index the new index name
      # @return [String] "OK"
      #
      # @see https://redis.io/commands/ft-alias-update/
      def ft_alias_update(alias_name, index)
        send_command(RequestType::FT_ALIAS_UPDATE, [alias_name, index])
      end

      # Create an index with the specified schema.
      #
      # @example Create a simple index
      #   valkey.ft_create("idx", "ON", "HASH", "PREFIX", "1", "doc:")
      # @example Create an index with schema
      #   valkey.ft_create("idx", "ON", "HASH", "PREFIX", "1", "doc:", "SCHEMA", "title", "TEXT", "body", "TEXT")
      #
      # @param [String] index the index name
      # @param [Array<String>] args index creation arguments (ON, PREFIX, SCHEMA, etc.)
      # @return [String] "OK"
      #
      # @see https://redis.io/commands/ft-create/
      def ft_create(index, *args)
        send_command(RequestType::FT_CREATE, [index, *args])
      end

      # Drop an index.
      #
      # @example
      #   valkey.ft_drop_index("idx")
      #     # => "OK"
      # @example Drop with DD option to also drop associated documents
      #   valkey.ft_drop_index("idx", dd: true)
      #     # => "OK"
      #
      # @param [String] index the index name
      # @param [Boolean] dd if true, also drop associated documents
      # @return [String] "OK"
      #
      # @see https://redis.io/commands/ft-dropindex/
      def ft_drop_index(index, dd: false)
        args = [index]
        args << "DD" if dd
        send_command(RequestType::FT_DROP_INDEX, args)
      end

      # Return the execution plan for a query.
      #
      # @example
      #   valkey.ft_explain("idx", "hello world")
      #     # => "INTERSECT { ... }"
      #
      # @param [String] index the index name
      # @param [String] query the query string
      # @return [String] execution plan description
      #
      # @see https://redis.io/commands/ft-explain/
      def ft_explain(index, query)
        send_command(RequestType::FT_EXPLAIN, [index, query])
      end

      # Return the execution plan for a query in a format suitable for CLI.
      #
      # @example
      #   valkey.ft_explain_cli("idx", "hello world")
      #     # => formatted execution plan
      #
      # @param [String] index the index name
      # @param [String] query the query string
      # @return [String] CLI-formatted execution plan
      #
      # @see https://redis.io/commands/ft-explaincli/
      def ft_explain_cli(index, query)
        send_command(RequestType::FT_EXPLAIN_CLI, [index, query])
      end

      # Return information and statistics about an index.
      #
      # @example
      #   valkey.ft_info("idx")
      #     # => {"index_name" => "idx", "index_definition" => {...}, ...}
      #
      # @param [String] index the index name
      # @return [Hash] index information and statistics
      #
      # @see https://redis.io/commands/ft-info/
      def ft_info(index)
        send_command(RequestType::FT_INFO, [index])
      end

      # Profile the execution of a query.
      #
      # @example
      #   valkey.ft_profile("idx", "SEARCH", "hello world")
      # @example Profile with aggregation
      #   valkey.ft_profile("idx", "AGGREGATE", "*", "GROUPBY", "1", "@field")
      #
      # @param [String] index the index name
      # @param [String] type the query type ("SEARCH" or "AGGREGATE")
      # @param [Array<String>] args query arguments
      # @return [Array] profiling results
      #
      # @see https://redis.io/commands/ft-profile/
      def ft_profile(index, type, *args)
        send_command(RequestType::FT_PROFILE, [index, type, *args])
      end

      # Search the index with a query.
      #
      # @example Simple search
      #   valkey.ft_search("idx", "hello world")
      # @example Search with options
      #   valkey.ft_search("idx", "hello", "LIMIT", "0", "10", "RETURN", "2", "title", "body")
      #
      # @param [String] index the index name
      # @param [String] query the query string
      # @param [Array<String>] args additional search options (LIMIT, RETURN, SORTBY, etc.)
      # @return [Array] search results
      #
      # @see https://redis.io/commands/ft-search/
      def ft_search(index, query, *args)
        send_command(RequestType::FT_SEARCH, [index, query, *args])
      end
    end
  end
end
