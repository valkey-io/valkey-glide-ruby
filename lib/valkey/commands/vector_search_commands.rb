# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands related to RediSearch Vector Search.
    #
    # RediSearch provides secondary indexing, full-text search, and vector similarity search
    # capabilities on top of Redis/Valkey. These commands require the RediSearch module to be loaded.
    #
    # @see https://redis.io/docs/stack/search/
    #
    module VectorSearchCommands
      # List all available indexes.
      #
      # @example List all indexes
      #   valkey.ft_list
      #     # => ["idx1", "idx2"]
      #
      # @return [Array<String>] array of index names
      #
      # @see https://redis.io/commands/ft._list/
      def ft_list
        send_command(RequestType::FT_LIST)
      end

      # Run a search query with aggregations.
      #
      # @example Perform an aggregation query
      #   valkey.ft_aggregate("myIndex", "*", "GROUPBY", "1", "@category", "REDUCE", "COUNT", "0", "AS", "count")
      #     # => [[1, ["category", "electronics", "count", "5"]]]
      #
      # @param [String] index the index name to search
      # @param [String] query the search query
      # @param [Array<String>] args additional query arguments (GROUPBY, REDUCE, etc.)
      # @return [Array] aggregation results
      #
      # @see https://redis.io/commands/ft.aggregate/
      def ft_aggregate(index, query, *args)
        command_args = [index, query] + args
        send_command(RequestType::FT_AGGREGATE, command_args)
      end

      # Add an alias to an index.
      #
      # @example Add an alias to an index
      #   valkey.ft_alias_add("myAlias", "myIndex")
      #     # => "OK"
      #
      # @param [String] alias the alias name
      # @param [String] index the index name
      # @return [String] "OK" on success
      #
      # @see https://redis.io/commands/ft.aliasadd/
      def ft_alias_add(alias_name, index)
        send_command(RequestType::FT_ALIAS_ADD, [alias_name, index])
      end

      # Delete an alias from an index.
      #
      # @example Delete an alias
      #   valkey.ft_alias_del("myAlias")
      #     # => "OK"
      #
      # @param [String] alias the alias name to delete
      # @return [String] "OK" on success
      #
      # @see https://redis.io/commands/ft.aliasdel/
      def ft_alias_del(alias_name)
        send_command(RequestType::FT_ALIAS_DEL, [alias_name])
      end

      # List all existing aliases.
      #
      # @example List all aliases
      #   valkey.ft_alias_list
      #     # => ["alias1", "alias2"]
      #
      # @return [Array<String>] array of alias names
      #
      # @see https://redis.io/commands/ft.aliaslist/
      def ft_alias_list
        send_command(RequestType::FT_ALIAS_LIST)
      end

      # Update an alias to point to a different index.
      #
      # @example Update an alias
      #   valkey.ft_alias_update("myAlias", "newIndex")
      #     # => "OK"
      #
      # @param [String] alias the alias name
      # @param [String] index the new index name
      # @return [String] "OK" on success
      #
      # @see https://redis.io/commands/ft.aliasupdate/
      def ft_alias_update(alias_name, index)
        send_command(RequestType::FT_ALIAS_UPDATE, [alias_name, index])
      end

      # Create a search index with the given schema.
      #
      # @example Create a basic index
      #   valkey.ft_create("myIndex", "SCHEMA", "title", "TEXT", "price", "NUMERIC")
      #     # => "OK"
      #
      # @example Create an index with vector field
      #   valkey.ft_create("vecIndex", "ON", "HASH", "PREFIX", "1", "doc:",
      #                    "SCHEMA", "embedding", "VECTOR", "HNSW", "6",
      #                    "TYPE", "FLOAT32", "DIM", "128", "DISTANCE_METRIC", "COSINE")
      #     # => "OK"
      #
      # @param [String] index the index name
      # @param [Array<String>] args schema definition and options
      # @return [String] "OK" on success
      #
      # @see https://redis.io/commands/ft.create/
      def ft_create(index, *args)
        command_args = [index] + args
        send_command(RequestType::FT_CREATE, command_args)
      end

      # Drop an index and optionally delete all documents.
      #
      # @example Drop an index without deleting documents
      #   valkey.ft_drop_index("myIndex")
      #     # => "OK"
      #
      # @example Drop an index and delete all documents
      #   valkey.ft_drop_index("myIndex", dd: true)
      #     # => "OK"
      #
      # @param [String] index the index name
      # @param [Boolean] dd whether to delete documents (DD flag)
      # @return [String] "OK" on success
      #
      # @see https://redis.io/commands/ft.dropindex/
      def ft_drop_index(index, dd: false)
        args = [index]
        args << "DD" if dd
        send_command(RequestType::FT_DROP_INDEX, args)
      end

      # Explain how a query is parsed and executed.
      #
      # @example Explain a query
      #   valkey.ft_explain("myIndex", "@title:hello @price:[0 100]")
      #     # => "INTERSECT {\n  @title:hello\n  @price:[0 100]\n}\n"
      #
      # @param [String] index the index name
      # @param [String] query the search query
      # @param [Array<String>] args additional query arguments
      # @return [String] query execution plan
      #
      # @see https://redis.io/commands/ft.explain/
      def ft_explain(index, query, *args)
        command_args = [index, query] + args
        send_command(RequestType::FT_EXPLAIN, command_args)
      end

      # Explain how a query is parsed and executed (CLI-formatted output).
      #
      # @example Explain a query in CLI format
      #   valkey.ft_explain_cli("myIndex", "@title:hello")
      #     # => formatted query plan
      #
      # @param [String] index the index name
      # @param [String] query the search query
      # @param [Array<String>] args additional query arguments
      # @return [String] formatted query execution plan
      #
      # @see https://redis.io/commands/ft.explaincli/
      def ft_explain_cli(index, query, *args)
        command_args = [index, query] + args
        send_command(RequestType::FT_EXPLAIN_CLI, command_args)
      end

      # Get information about an index.
      #
      # @example Get index info
      #   valkey.ft_info("myIndex")
      #     # => ["index_name", "myIndex", "fields", [...], ...]
      #
      # @param [String] index the index name
      # @return [Array] index information as array of key-value pairs
      #
      # @see https://redis.io/commands/ft.info/
      def ft_info(index)
        send_command(RequestType::FT_INFO, [index])
      end

      # Profile a search or aggregation query.
      #
      # @example Profile a search query
      #   valkey.ft_profile("myIndex", "SEARCH", "QUERY", "@title:hello")
      #     # => [execution time, results]
      #
      # @example Profile an aggregation query
      #   valkey.ft_profile("myIndex", "AGGREGATE", "QUERY", "*", "GROUPBY", "1", "@category")
      #     # => [execution time, results]
      #
      # @param [String] index the index name
      # @param [String] query_type either "SEARCH" or "AGGREGATE"
      # @param [Array<String>] args query arguments
      # @return [Array] profiling results with execution time and query results
      #
      # @see https://redis.io/commands/ft.profile/
      def ft_profile(index, query_type, *args)
        command_args = [index, query_type] + args
        send_command(RequestType::FT_PROFILE, command_args)
      end

      # Search an index with a query.
      #
      # @example Basic search
      #   valkey.ft_search("myIndex", "hello world")
      #     # => [1, "doc1", ["title", "hello world"]]
      #
      # @example Search with options
      #   valkey.ft_search("myIndex", "@title:hello", "LIMIT", "0", "10", "RETURN", "2", "title", "price")
      #     # => [total_results, doc_id, [field1, value1, field2, value2], ...]
      #
      # @example Vector similarity search
      #   valkey.ft_search("vecIndex", "*=>[KNN 5 @embedding $vec]",
      #                    "PARAMS", "2", "vec", vector_blob,
      #                    "RETURN", "1", "__embedding_score",
      #                    "DIALECT", "2")
      #     # => [results_count, doc_id, ["__embedding_score", "0.95"], ...]
      #
      # @param [String] index the index name
      # @param [String] query the search query
      # @param [Array<String>] args additional query arguments (LIMIT, RETURN, SORTBY, etc.)
      # @return [Array] search results with total count and matching documents
      #
      # @see https://redis.io/commands/ft.search/
      def ft_search(index, query, *args)
        command_args = [index, query] + args
        send_command(RequestType::FT_SEARCH, command_args)
      end

      # Convenience method for FT.* commands.
      #
      # @example List indexes
      #   valkey.ft(:list)
      #     # => ["idx1", "idx2"]
      #
      # @example Create an index
      #   valkey.ft(:create, "myIndex", "SCHEMA", "title", "TEXT")
      #     # => "OK"
      #
      # @example Search an index
      #   valkey.ft(:search, "myIndex", "hello")
      #     # => [results]
      #
      # @param [String, Symbol] subcommand the subcommand (list, create, search, etc.)
      # @param [Array] args arguments for the subcommand
      # @param [Hash] options options for the subcommand
      # @return [Object] depends on subcommand
      def ft(subcommand, *args, **options)
        subcommand = subcommand.to_s.downcase.gsub("-", "_")

        if args.empty? && options.empty?
          send("ft_#{subcommand}")
        elsif options.empty?
          send("ft_#{subcommand}", *args)
        else
          send("ft_#{subcommand}", *args, **options)
        end
      end
    end
  end
end
