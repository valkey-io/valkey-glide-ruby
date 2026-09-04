# frozen_string_literal: true

class Valkey
  module Commands
    # Commands for Valkey Search (the FT.* command family): secondary indexing,
    # full-text search, aggregation, and vector similarity search. They require
    # the search module to be loaded on the server.
    #
    # @see https://valkey.io/commands/#search
    module VectorSearchCommands
      # List all available indexes.
      #
      # @example List all indexes
      #   valkey.ft_list
      #     # => ["idx1", "idx2"]
      #
      # @return [Array<String>] array of index names
      #
      # @see https://valkey.io/commands/ft._list/
      def ft_list
        send_command(RequestType::FT_LIST)
      end

      # Create a search index with the given schema.
      #
      # Pass an Array of {Valkey::Search::Field} objects and, optionally, a
      # {Valkey::Search::CreateOptions} (or the same index-level options as
      # keyword arguments):
      #
      #     valkey.ft_create("idx",
      #       [Valkey::Search::TextField.new("title", sortable: true),
      #        Valkey::Search::VectorField.hnsw("embedding", dim: 128, metric: :cosine)],
      #       on: :hash, prefixes: ["doc:"])
      #
      # In cluster mode the index definition is per-node, so FT.CREATE is
      # broadcast to every primary (otherwise a query routed to another shard
      # fails with "Index with name '...' not found"). Pass an explicit `route:`
      # to override.
      #
      # @param index [String] the index name
      # @param fields [Array<Valkey::Search::Field>] the schema
      # @param options [Valkey::Search::CreateOptions, nil] index-level options
      # @param route [Valkey::Route, nil] override the all-primaries broadcast
      # @param kwargs [Hash] index-level options, as an alternative to +options+
      #   (forwarded to {Valkey::Search::CreateOptions})
      # @return [String, Hash] "OK" when every node agrees (the usual case);
      #   the per-node `{ "host:port" => reply }` Hash if they disagree
      # @raise [ArgumentError] on an empty/invalid schema, a non-CreateOptions
      #   options object, or options passed both positionally and as keywords
      #
      # @see https://valkey.io/commands/ft.create/
      def ft_create(index, fields, options = nil, route: nil, **kwargs)
        command_args = ft_create_args(index, fields, options, kwargs)
        ft_collapse_broadcast(
          send_command(RequestType::FT_CREATE, command_args, route: route || ft_all_primaries_route)
        )
      end

      # Drop an index. Indexed documents are always preserved.
      #
      # Valkey Search has no DD flag (FT.DROPINDEX takes the index name only),
      # so the underlying documents are never deleted.
      #
      # Like {#ft_create}, this is broadcast to every primary in cluster mode
      # because the index definition is per-node.
      #
      # @example Drop an index
      #   valkey.ft_drop_index("myIndex")
      #     # => "OK"
      #
      # @param index [String] the index name
      # @param route [Valkey::Route, nil] override the all-primaries broadcast
      # @return [String, Hash] "OK" when every node agrees (the usual case); the
      #   per-node `{ "host:port" => reply }` Hash if they disagree
      #
      # @see https://valkey.io/commands/ft.dropindex/
      def ft_drop_index(index, route: nil)
        ft_collapse_broadcast(
          send_command(RequestType::FT_DROP_INDEX, [index], route: route || ft_all_primaries_route)
        )
      end

      # Get information about an index.
      #
      # Options are optional: pass a {Valkey::Search::InfoOptions} (or the same
      # options as keyword arguments) to add a scope / cluster flags.
      #
      #     valkey.ft_info("idx")
      #     valkey.ft_info("idx", scope: :cluster, consistency: :consistent)
      #     valkey.ft_info("idx", Valkey::Search::InfoOptions.new(scope: :local))
      #
      # @param index [String] the index name
      # @param options [Valkey::Search::InfoOptions, nil] info options
      # @param kwargs [Hash] info options, as an alternative to +options+
      #   (forwarded to {Valkey::Search::InfoOptions})
      # @return [Hash] index information as a hash of key-value pairs
      # @raise [ArgumentError] on options passed both positionally and as keywords
      #
      # @see https://valkey.io/commands/ft.info/
      def ft_info(index, options = nil, **kwargs)
        resolved = ft_resolve_options(Valkey::Search::InfoOptions, options, kwargs, label: "ft_info")
        command_args = [index]
        command_args.concat(resolved.to_args) if resolved
        send_command(RequestType::FT_INFO, command_args)
      end

      # Search an index with a query, returning a structured
      # {Valkey::Search::SearchResult}.
      #
      #     result = valkey.ft_search("idx", "@title:hello",
      #       Valkey::Search::SearchOptions.new(limit: { offset: 0, count: 10 }, sort_by: "price"))
      #     result.total_results  # => Integer
      #     result.documents      # => [#<struct Document key=..., fields={...}>, ...]
      #
      #     valkey.ft_search("idx", "@title:hello", limit: { offset: 0, count: 10 })
      #
      # ### Limitations
      #
      # * **`flatten_map: true` is not supported.** That's the `Valkey.new(...,
      #   flatten_map: true)` client-wide constructor option (a redis-rb 4.x
      #   compatibility shim, unrelated to the FT.* builders), which flattens
      #   every map reply — destroying the structure {Valkey::Search::SearchResult}
      #   parses.
      # * **Not supported inside `pipelined` / `multi`.** Commands queued in a
      #   batch return a {Valkey::Future} rather than a reply, so there is nothing
      #   to parse into a SearchResult.
      #
      # In both cases use {Valkey#call} to issue FT.SEARCH directly and handle the
      # raw reply yourself.
      #
      # @param index [String] the index name
      # @param query [String] the search query
      # @param options [Valkey::Search::SearchOptions, nil] search options
      # @param kwargs [Hash] search options, as an alternative to +options+
      #   (forwarded to {Valkey::Search::SearchOptions})
      # @return [Valkey::Search::SearchResult] the structured result
      # @raise [ArgumentError] on options passed both positionally and as
      #   keywords, or when used inside a batch or with `flatten_map: true`
      #
      # @see https://valkey.io/commands/ft.search/
      def ft_search(index, query, options = nil, **kwargs)
        ft_assert_supported!("ft_search")
        resolved = ft_resolve_options(Valkey::Search::SearchOptions, options, kwargs, label: "ft_search") ||
                   Valkey::Search::SearchOptions.new
        raw = send_command(RequestType::FT_SEARCH, [index, query] + resolved.to_args)
        Valkey::Search::SearchResult.from_raw(
          raw, no_content: resolved.no_content, with_sort_keys: resolved.with_sort_keys
        )
      end

      # Run an aggregation pipeline over an index.
      #
      # Pass a {Valkey::Search::AggregateOptions} (or the same options as keyword
      # arguments, including an ordered +clauses:+ array):
      #
      #     valkey.ft_aggregate("idx", "@price:[0 +inf]",
      #       clauses: [
      #         Valkey::Search::GroupBy.new(["@category"],
      #           reducers: [Valkey::Search::Reducer.count(as: "count")]),
      #         Valkey::Search::SortBy.new("@count", :desc),
      #         Valkey::Search::Limit.new(0, 10),
      #       ], dialect: 2)
      #
      # Note that Valkey Search rejects the `"*"` wildcard here — use a filter
      # expression such as `"@price:[0 +inf]"` as the query.
      #
      # Not supported inside `pipelined` / `multi`, matching every other FT.*
      # command and the other GLIDE clients: a queued command returns a
      # {Valkey::Future} rather than a reply. Use {Valkey#call} to issue
      # FT.AGGREGATE directly inside a batch.
      #
      # @param index [String] the index name to search
      # @param query [String] the search/filter query
      # @param options [Valkey::Search::AggregateOptions, nil] aggregate options
      # @param kwargs [Hash] aggregate options, as an alternative to +options+
      #   (forwarded to {Valkey::Search::AggregateOptions})
      # @return [Array] aggregation results
      # @raise [ArgumentError] on options passed both positionally and as
      #   keywords, or when used inside a batch
      #
      # @see https://valkey.io/commands/ft.aggregate/
      def ft_aggregate(index, query, options = nil, **kwargs)
        ft_assert_supported!("ft_aggregate", flatten_map_check: false)
        resolved = ft_resolve_options(Valkey::Search::AggregateOptions, options, kwargs, label: "ft_aggregate")
        command_args = [index, query]
        command_args.concat(resolved.to_args) if resolved
        send_command(RequestType::FT_AGGREGATE, command_args)
      end

      private

      # Resolve an options object from either a positional instance or keyword
      # arguments, rejecting both at once. Returns nil when neither is given.
      #
      # @api private
      # @param klass [Class] the options class
      # @param options [Object, nil] a positional options instance
      # @param kwargs [Hash] keyword options
      # @param label [String] command name, for error messages
      # @return [Object, nil] an instance of klass, or nil
      # @raise [ArgumentError] on a wrong-typed positional, or options given both ways
      def ft_resolve_options(klass, options, kwargs, label:)
        short = klass.name.split("::").last
        if options.nil?
          kwargs.empty? ? nil : klass.new(**kwargs)
        else
          raise ArgumentError, "#{label} options must be a #{klass}, got #{options.class}" unless options.is_a?(klass)
          unless kwargs.empty?
            raise ArgumentError,
                  "pass options to #{label} either as a #{short} object or as keyword arguments, not both"
          end

          options
        end
      end

      # Build the FT.CREATE token array from the schema + options.
      #
      # @api private
      # @raise [ArgumentError] on an empty/invalid schema, a non-CreateOptions
      #   options object, or options passed both ways
      def ft_create_args(index, fields, options, kwargs)
        unless fields.is_a?(Array)
          raise ArgumentError, "ft_create schema must be an Array of Valkey::Search::Field, got #{fields.class}"
        end
        raise ArgumentError, "schema must contain at least one field" if fields.empty?
        unless fields.all?(Valkey::Search::Field)
          raise ArgumentError, "every schema field must be a Valkey::Search::Field"
        end

        resolved = ft_resolve_options(Valkey::Search::CreateOptions, options, kwargs, label: "ft_create")

        command_args = [index]
        command_args.concat(resolved.to_args) if resolved
        command_args << "SCHEMA"
        fields.each { |field| command_args.concat(field.to_args) }
        command_args
      end

      # A broadcast route makes glide-core return `{ "host:port" => reply }`. When
      # every node replied identically (the normal case for FT.CREATE /
      # FT.DROPINDEX) collapse it back to the single value, so cluster and
      # standalone callers see the same "OK". A genuine per-node disagreement is
      # returned as-is rather than hidden.
      #
      # @api private
      def ft_collapse_broadcast(reply)
        return reply unless reply.is_a?(Hash) && !reply.empty?

        values = reply.values.uniq
        values.length == 1 ? values.first : reply
      end

      # Index definitions are per-node in Valkey Search, so FT.CREATE /
      # FT.DROPINDEX must reach every primary in cluster mode — a single-node
      # create leaves other shards answering "Index with name '...' not found".
      # Returns nil on standalone (and wherever routing is unavailable, e.g. a
      # queued batch), which leaves the command's default routing untouched.
      #
      # @api private
      def ft_all_primaries_route
        return nil unless @cluster_mode
        return nil unless defined?(Valkey::Route)

        Valkey::Route.all_primaries
      end

      # ft_search parses the reply into a structured result, which is incompatible
      # with two redis-rb compatibility behaviors: a queued batch yields a
      # {Valkey::Future} instead of a reply, and `flatten_map: true` flattens the
      # map structure the parser depends on. ft_aggregate returns the raw reply
      # unparsed, so only the batch restriction applies there (flatten_map_check:
      # false) — matching the other GLIDE clients, none of which support FT.*
      # commands inside a batch/transaction yet. Fail with a clear ArgumentError
      # instead of returning a corrupt result (or a NoMethodError from deep inside
      # the parser).
      #
      # @api private
      def ft_assert_supported!(method_name, flatten_map_check: true)
        if ft_queued_in_batch?
          raise ArgumentError,
                "#{method_name} is not supported inside pipelined/multi; " \
                "use Valkey#call to issue #{method_name == 'ft_search' ? 'FT.SEARCH' : 'FT.AGGREGATE'} " \
                "and handle the raw reply"
        end
        return unless flatten_map_check
        return unless instance_variable_defined?(:@flatten_map) && instance_variable_get(:@flatten_map)

        raise ArgumentError,
              "#{method_name} is not supported with flatten_map: true; " \
              "use Valkey#call to issue FT.SEARCH and handle the raw reply"
      end

      # True when this receiver queues commands instead of executing them: either
      # a Pipeline (which collects @commands/@futures) or a client inside MULTI.
      #
      # @api private
      def ft_queued_in_batch?
        return true if instance_variable_defined?(:@futures) && instance_variable_defined?(:@commands)

        instance_variable_defined?(:@in_multi) && instance_variable_get(:@in_multi)
      end
    end
  end
end
