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

      # Drop an index. Indexed documents are always preserved.
      #
      # Valkey Search has no DD flag (FT.DROPINDEX takes the index name only),
      # so the underlying documents are never deleted.
      #
      # @example Drop an index
      #   valkey.ft_drop_index("myIndex")
      #     # => "OK"
      #
      # @param index [String] the index name
      # @return [String] "OK" on success
      #
      # @see https://valkey.io/commands/ft.dropindex/
      def ft_drop_index(index)
        send_command(RequestType::FT_DROP_INDEX, [index])
      end

      # Get information about an index.
      #
      # Two calling styles are supported:
      #
      # 1. **Builder API** — pass a {Valkey::Search::InfoOptions} (or the same
      #    options as keyword arguments) to add a scope / cluster flags:
      #
      #        valkey.ft_info("idx", scope: :cluster, consistency: :consistent)
      #        valkey.ft_info("idx", Valkey::Search::InfoOptions.new(scope: :local))
      #
      # 2. **Plain** (backward compatible) — no options yields `FT.INFO <index>`:
      #
      #        valkey.ft_info("idx")
      #
      # @param index [String] the index name
      # @param args [Array] a lone InfoOptions (builder) or nothing
      # @param kwargs [Hash] info options for the builder path (forwarded to
      #   {Valkey::Search::InfoOptions})
      # @return [Hash] index information as a hash of key-value pairs
      # @raise [ArgumentError] on a malformed builder invocation
      #
      # @see https://redis.io/commands/ft.info/
      def ft_info(index, *args, **kwargs)
        options = ft_info_options(args, kwargs)
        command_args = [index]
        command_args.concat(options.to_args) if options
        send_command(RequestType::FT_INFO, command_args)
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
      # ### Limitations of the builder path
      #
      # * **`flatten_map: true` is not supported.** That client option is a
      #   redis-rb 4.x compatibility shim that flattens every map reply, which
      #   destroys the structure {Valkey::Search::SearchResult} parses. Use the
      #   raw-args path when the client is constructed with `flatten_map: true`.
      # * **Not supported inside `pipelined` / `multi`.** Commands queued in a
      #   batch return a {Valkey::Future} rather than a reply, so there is nothing
      #   to parse into a SearchResult. Use the raw-args path in a batch, or issue
      #   the builder call outside it.
      #
      # @param index [String] the index name
      # @param query [String] the search query
      # @param args [Array] a lone SearchOptions (builder) or raw FT.SEARCH tokens
      # @param kwargs [Hash] search options for the builder path (forwarded to
      #   {Valkey::Search::SearchOptions}); ignored on the raw-args path
      # @return [Valkey::Search::SearchResult, Array] structured result on the
      #   builder path; the raw reply Array on the raw path
      # @raise [ArgumentError] on a malformed builder invocation, or when the
      #   builder path is used inside a batch or with `flatten_map: true`
      #
      # @see https://valkey.io/commands/ft.search/
      def ft_search(index, query, *args, **kwargs)
        options = ft_search_options(args, kwargs)
        if options
          ft_assert_builder_supported!("ft_search")
          command_args = [index, query] + options.to_args
          raw = send_command(RequestType::FT_SEARCH, command_args)
          Valkey::Search::SearchResult.from_raw(
            raw, no_content: options.no_content, with_sort_keys: options.with_sort_keys
          )
        else
          send_command(RequestType::FT_SEARCH, [index, query] + args)
        end
      end

      private

      # The builder path parses the reply into a structured result, which is
      # incompatible with two redis-rb compatibility behaviors: a queued batch
      # yields a {Valkey::Future} instead of a reply, and `flatten_map: true`
      # flattens the map structure the parser depends on. Fail with a clear
      # ArgumentError instead of returning a corrupt result (or a NoMethodError
      # from deep inside the parser).
      #
      # The batch check is duck-typed rather than `is_a?(Valkey::Pipeline)` so it
      # holds even when pipeline.rb has not been loaded (the class name is only
      # compared when the constant is actually defined).
      def ft_assert_builder_supported!(method_name)
        if ft_queued_in_batch?
          raise ArgumentError,
                "#{method_name} builder options are not supported inside pipelined/multi; " \
                "queue raw FT.SEARCH tokens instead"
        end
        return unless instance_variable_defined?(:@flatten_map) && instance_variable_get(:@flatten_map)

        raise ArgumentError,
              "#{method_name} builder options are not supported with flatten_map: true; " \
              "use the raw-args form on a flatten_map client"
      end

      # True when this receiver queues commands instead of executing them: either
      # a Pipeline (which collects @commands/@futures) or a client inside MULTI.
      def ft_queued_in_batch?
        return true if instance_variable_defined?(:@futures) && instance_variable_defined?(:@commands)

        instance_variable_defined?(:@in_multi) && instance_variable_get(:@in_multi)
      end

      # Shared resolver for the builder-vs-raw dispatch used by ft_search,
      # ft_aggregate, and ft_info. Returns an options instance (built from a lone
      # positional options object, or from keyword args), or nil for the
      # raw/plain path. Validates the invocation up front — a malformed call
      # raises rather than silently degrading.
      #
      # @param klass [Class] the options class (SearchOptions/AggregateOptions/InfoOptions)
      # @param args [Array] positional args after the fixed leading arguments
      # @param kwargs [Hash] keyword options
      # @param label [String] command label for error messages (e.g. "ft_search")
      # @param leading [String] what the options follow (e.g. "the query", "the index")
      # @param allow_raw [Boolean] whether trailing raw positionals are permitted
      #   (true → returns nil for the raw path; false → rejects extra positionals)
      # @return [Object, nil] an instance of klass, or nil for the raw/plain path
      # @raise [ArgumentError] on a malformed invocation
      def resolve_search_options(klass, args, kwargs, label:, leading:, allow_raw:)
        first = args[0]
        short = klass.name.split("::").last
        if first.is_a?(klass)
          raise ArgumentError, "#{label} takes a single #{short} after #{leading}" if args.length > 1
          unless kwargs.empty?
            raise ArgumentError, "pass options to #{label} either as a #{short} " \
                                 "object or as keyword arguments, not both"
          end

          first
        elsif args.empty?
          kwargs.empty? ? nil : klass.new(**kwargs)
        elsif allow_raw
          # Raw tokens present; kwargs would be silently dropped, so reject the mix.
          unless kwargs.empty?
            raise ArgumentError, "cannot mix raw #{label} tokens with keyword options; " \
                                 "use a #{short} object or pass all tokens raw"
          end

          nil
        else
          raise ArgumentError,
                "#{label} takes an optional #{short} or keyword options, got #{args.inspect}"
        end
      end

      # @see #resolve_search_options
      def ft_search_options(args, kwargs)
        resolve_search_options(Valkey::Search::SearchOptions, args, kwargs,
                               label: "ft_search", leading: "the query", allow_raw: true)
      end

      # @see #resolve_search_options
      def ft_aggregate_options(args, kwargs)
        resolve_search_options(Valkey::Search::AggregateOptions, args, kwargs,
                               label: "ft_aggregate", leading: "the query", allow_raw: true)
      end

      # @see #resolve_search_options
      def ft_info_options(args, kwargs)
        resolve_search_options(Valkey::Search::InfoOptions, args, kwargs,
                               label: "ft_info", leading: "the index", allow_raw: false)
      end

      # Build the FT.CREATE token array from field builders + options, validating
      # the builder invocation up front. Any malformed input raises ArgumentError
      # rather than silently degrading.
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
          # a lone Array selects the builder path, so raw FT.CREATE
          # tokens passed as one Array land here. Hint at the splat requirement.
          hint =
            if fields.all?(String)
              " (did you mean to splat these as raw FT.CREATE tokens, e.g. ft_create(index, *tokens)?)"
            else
              ""
            end
          raise ArgumentError, "every schema field must be a Valkey::Search::Field#{hint}"
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
