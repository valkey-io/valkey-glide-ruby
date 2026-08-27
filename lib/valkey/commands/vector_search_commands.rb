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
      # Two calling styles are supported:
      #
      # 1. **Builder API** — pass a {Valkey::Search::AggregateOptions} (or the same
      #    options as keyword arguments, including an ordered +clauses:+ array):
      #
      #        valkey.ft_aggregate("idx", "@price:[0 +inf]",
      #          clauses: [
      #            Valkey::Search::GroupBy.new(["@category"],
      #              reducers: [Valkey::Search::Reducer.count(as: "count")]),
      #            Valkey::Search::SortBy.new("@count", :desc),
      #            Valkey::Search::Limit.new(0, 10),
      #          ], dialect: 2)
      #
      # 2. **Raw args** (backward compatible) — pass FT.AGGREGATE tokens directly:
      #
      #        # Valkey-native FT.AGGREGATE rejects the "*" wildcard; use a filter.
      #        valkey.ft_aggregate("idx", "@price:[0 +inf]",
      #                            "GROUPBY", "1", "@category", "REDUCE", "COUNT", "0", "AS", "count")
      #
      # The builder path is selected when the first argument after +query+ is an
      # {Valkey::Search::AggregateOptions}, or when only keyword options are given.
      # Any other positional arguments are forwarded verbatim (raw path).
      #
      # @param index [String] the index name to search
      # @param query [String] the search/filter query
      # @param args [Array] a lone AggregateOptions (builder) or raw tokens
      # @param kwargs [Hash] aggregate options for the builder path (forwarded to
      #   {Valkey::Search::AggregateOptions}); ignored on the raw-args path
      # @return [Array] aggregation results
      # @raise [ArgumentError] on a malformed builder invocation
      #
      # @see https://redis.io/commands/ft.aggregate/
      def ft_aggregate(index, query, *args, **kwargs)
        options = ft_aggregate_options(args, kwargs)
        command_args =
          if options
            [index, query] + options.to_args
          else
            [index, query] + args
          end
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
      # Two calling styles are supported:
      #
      # 1. **Builder API** — pass an Array of {Valkey::Search::Field} objects and,
      #    optionally, a {Valkey::Search::CreateOptions} (or the same index-level
      #    options as keyword arguments):
      #
      #        valkey.ft_create("idx",
      #          [Valkey::Search::TextField.new("title", sortable: true),
      #           Valkey::Search::VectorField.hnsw("embedding", dim: 128, metric: :cosine)],
      #          on: :hash, prefixes: ["doc:"])
      #
      # 2. **Raw args** (backward compatible) — pass the FT.CREATE tokens directly:
      #
      #        valkey.ft_create("idx", "SCHEMA", "title", "TEXT", "price", "NUMERIC")
      #
      #    Raw tokens must be splatted as individual arguments, not wrapped in an
      #    Array — a single Array argument selects the builder path (and raises if
      #    its elements are not {Valkey::Search::Field} objects).
      #
      # The builder path is selected as soon as the first argument after +index+
      # is an Array; from there the arguments are validated and any problem
      # raises ArgumentError rather than silently falling back to the raw path.
      # Anything else is forwarded verbatim as raw FT.CREATE tokens.
      #
      # @param index [String] the index name
      # @param args [Array] either `[fields]` / `[fields, create_options]` (builder)
      #   or raw FT.CREATE tokens
      # @param kwargs [Hash] index-level options for the builder path (forwarded to
      #   {Valkey::Search::CreateOptions}); ignored on the raw-args path
      # @return [String] "OK" on success
      # @raise [ArgumentError] on a malformed builder invocation
      #
      # @see https://redis.io/commands/ft.create/
      def ft_create(index, *args, **kwargs)
        command_args =
          if args[0].is_a?(Array)
            ft_create_builder_args(index, args, kwargs)
          else
            [index] + args
          end
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
      # @return [Hash] index information as a hash of key-value pairs
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
      # Two calling styles are supported:
      #
      # 1. **Builder API** — pass a {Valkey::Search::SearchOptions} (or the same
      #    options as keyword arguments). Returns a structured
      #    {Valkey::Search::SearchResult}:
      #
      #        result = valkey.ft_search("idx", "@title:hello",
      #          Valkey::Search::SearchOptions.new(limit: { offset: 0, count: 10 }, sort_by: "price"))
      #        result.total_results  # => Integer
      #        result.documents      # => [#<struct Document key=..., fields={...}>, ...]
      #
      #        valkey.ft_search("idx", "@title:hello", limit: { offset: 0, count: 10 })
      #
      # 2. **Raw args** (backward compatible) — pass FT.SEARCH tokens directly and
      #    get the raw reply Array back:
      #
      #        valkey.ft_search("idx", "@title:hello", "LIMIT", "0", "10")
      #
      # The builder path is selected when the first argument after +query+ is a
      # {Valkey::Search::SearchOptions}, or when only keyword options are given.
      # Any other positional arguments are forwarded verbatim (raw path).
      #
      # @param index [String] the index name
      # @param query [String] the search query
      # @param args [Array] a lone SearchOptions (builder) or raw FT.SEARCH tokens
      # @param kwargs [Hash] search options for the builder path (forwarded to
      #   {Valkey::Search::SearchOptions}); ignored on the raw-args path
      # @return [Valkey::Search::SearchResult, Array] structured result on the
      #   builder path; the raw reply Array on the raw path
      # @raise [ArgumentError] on a malformed builder invocation
      #
      # @see https://redis.io/commands/ft.search/
      def ft_search(index, query, *args, **kwargs)
        options = ft_search_options(args, kwargs)
        if options
          command_args = [index, query] + options.to_args
          raw = send_command(RequestType::FT_SEARCH, command_args)
          Valkey::Search::SearchResult.from_raw(
            raw, no_content: options.no_content, with_sort_keys: options.with_sort_keys
          )
        else
          send_command(RequestType::FT_SEARCH, [index, query] + args)
        end
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

        # public_send so ft() cannot reach private helpers (SEC-001).
        if args.empty? && options.empty?
          public_send("ft_#{subcommand}")
        elsif options.empty?
          public_send("ft_#{subcommand}", *args)
        else
          public_send("ft_#{subcommand}", *args, **options)
        end
      end

      private

      # Resolve the {Valkey::Search::SearchOptions} for an ft_search builder call,
      # or nil for the raw-args path. Validates the builder invocation up front
      # (same philosophy as ft_create): a malformed call raises rather than
      # silently degrading.
      #
      # @param args [Array] positional args after query
      # @param kwargs [Hash] keyword options
      # @return [Valkey::Search::SearchOptions, nil]
      # @raise [ArgumentError] on a non-SearchOptions positional, options passed
      #   both ways, or extra positionals alongside a SearchOptions
      def ft_search_options(args, kwargs)
        first = args[0]
        if first.is_a?(Valkey::Search::SearchOptions)
          raise ArgumentError, "ft_search takes a single SearchOptions after the query" if args.length > 1
          unless kwargs.empty?
            raise ArgumentError,
                  "pass search options either as a SearchOptions object or as keyword arguments, not both"
          end

          first
        elsif args.empty?
          kwargs.empty? ? nil : Valkey::Search::SearchOptions.new(**kwargs)
        else
          # Raw tokens present; kwargs would be silently dropped, so reject the mix.
          unless kwargs.empty?
            raise ArgumentError,
                  "cannot mix raw FT.SEARCH tokens with keyword search options; " \
                  "use a SearchOptions object or pass all tokens raw"
          end

          nil
        end
      end

      # Resolve the {Valkey::Search::AggregateOptions} for an ft_aggregate builder
      # call, or nil for the raw-args path. Same dispatch philosophy as ft_search:
      # a malformed builder invocation raises rather than silently degrading.
      #
      # @param args [Array] positional args after query
      # @param kwargs [Hash] keyword options
      # @return [Valkey::Search::AggregateOptions, nil]
      # @raise [ArgumentError] on a non-AggregateOptions positional, options passed
      #   both ways, or extra positionals alongside an AggregateOptions
      def ft_aggregate_options(args, kwargs)
        first = args[0]
        if first.is_a?(Valkey::Search::AggregateOptions)
          raise ArgumentError, "ft_aggregate takes a single AggregateOptions after the query" if args.length > 1
          unless kwargs.empty?
            raise ArgumentError,
                  "pass aggregate options either as an AggregateOptions object or as keyword arguments, not both"
          end

          first
        elsif args.empty?
          kwargs.empty? ? nil : Valkey::Search::AggregateOptions.new(**kwargs)
        else
          unless kwargs.empty?
            raise ArgumentError,
                  "cannot mix raw FT.AGGREGATE tokens with keyword aggregate options; " \
                  "use an AggregateOptions object or pass all tokens raw"
          end

          nil
        end
      end

      # the builder invocation up front (see F-DISPATCH findings). Any malformed
      # input raises ArgumentError rather than silently degrading.
      #
      # @param index [String] index name
      # @param args [Array] positional builder args: `[fields]` or `[fields, options]`
      # @param kwargs [Hash] option keyword arguments (used only when no positional
      #   options object is given)
      # @return [Array] flat FT.CREATE token array
      # @raise [ArgumentError] on too many positionals, an empty/invalid schema,
      #   a non-CreateOptions options object, or options passed both ways
      def ft_create_builder_args(index, args, kwargs)
        if args.length > 2
          raise ArgumentError,
                "ft_create builder form takes the schema and an optional CreateOptions " \
                "(got #{args.length} positional arguments)"
        end

        fields = args[0]
        options = args[1]

        raise ArgumentError, "schema must contain at least one field" if fields.empty?
        unless fields.all?(Valkey::Search::Field)
          raise ArgumentError, "every schema field must be a Valkey::Search::Field"
        end
        unless options.nil? || options.is_a?(Valkey::Search::CreateOptions)
          raise ArgumentError,
                "ft_create options must be a Valkey::Search::CreateOptions, got #{options.class}"
        end
        if options && !kwargs.empty?
          raise ArgumentError,
                "pass index options either as a CreateOptions object or as keyword arguments, not both"
        end

        options ||= Valkey::Search::CreateOptions.new(**kwargs) unless kwargs.empty?

        command_args = [index]
        command_args.concat(options.to_args) if options
        command_args << "SCHEMA"
        fields.each { |field| command_args.concat(field.to_args) }
        command_args
      end
    end
  end
end
