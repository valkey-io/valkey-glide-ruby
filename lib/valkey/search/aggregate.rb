# frozen_string_literal: true

class Valkey
  module Search
    # Pipeline clauses and options for FT.AGGREGATE. Clauses (GroupBy, SortBy,
    # Filter, Limit, Apply) serialize in the order the user supplies them, since
    # FT.AGGREGATE is an ordered pipeline. Flat top-level options (verbatim, load,
    # params, dialect, timeout, shard_scope, consistency) are keyword arguments on
    # {AggregateOptions}. Mirrors the Java FTAggregateOptions surface, adapted to
    # Ruby idiom.
    #
    # @see https://redis.io/commands/ft.aggregate/

    # A single REDUCE within a GROUPBY. Emits `REDUCE <function> <nargs> <arg...>
    # [AS <name>]`. The nargs count is the number of argument tokens that follow
    # the function name, matching the wire format and Java.
    #
    # @example
    #   Valkey::Search::Reducer.count(as: "total")
    #   Valkey::Search::Reducer.sum("@price", as: "revenue")
    class Reducer
      # @return [String] the reducer function (e.g. "COUNT", "SUM")
      attr_reader :function
      # @return [Array] the reducer argument tokens (properties/values)
      attr_reader :args
      # @return [String, nil] optional result alias (AS clause)
      attr_reader :alias_name

      # @param function [String, Symbol] reducer function name
      # @param args [Array] argument tokens following the function
      # @param as [String, nil] optional AS alias
      def initialize(function, *args, as: nil)
        @function = function.to_s.upcase
        @args = args
        @alias_name = as
      end

      # COUNT — number of records in the group. Takes no property.
      def self.count(as: nil)
        new("COUNT", as: as)
      end

      # COUNT_DISTINCT of a property.
      def self.count_distinct(property, as: nil)
        new("COUNT_DISTINCT", property, as: as)
      end

      # SUM of a numeric property.
      def self.sum(property, as: nil)
        new("SUM", property, as: as)
      end

      # MIN of a property.
      def self.min(property, as: nil)
        new("MIN", property, as: as)
      end

      # MAX of a property.
      def self.max(property, as: nil)
        new("MAX", property, as: as)
      end

      # AVG of a numeric property.
      def self.avg(property, as: nil)
        new("AVG", property, as: as)
      end

      # STDDEV of a numeric property.
      def self.stddev(property, as: nil)
        new("STDDEV", property, as: as)
      end

      # @return [Array] `REDUCE <function> <nargs> <arg...> [AS <name>]`
      def to_args
        tokens = ["REDUCE", @function, @args.length, *@args]
        tokens.push("AS", @alias_name) unless @alias_name.nil?
        tokens
      end
    end

    # Base class for an aggregate pipeline clause. Subclasses implement #to_args.
    # @abstract
    class AggregateClause
      # @return [Array] the flat FT.AGGREGATE token array for this clause
      def to_args
        raise NotImplementedError, "#{self.class} must implement #to_args"
      end
    end

    # GROUPBY clause: `GROUPBY <nprops> <property...> [REDUCE ...]...`. The nprops
    # count is the number of grouping properties; each reducer appends its own
    # `REDUCE ...` run after them.
    #
    # @example
    #   Valkey::Search::GroupBy.new(["@category"],
    #     reducers: [Valkey::Search::Reducer.count(as: "total")])
    class GroupBy < AggregateClause
      # @param properties [Array<String>] grouping properties (may be empty for a
      #   global aggregation, matching `GROUPBY 0`)
      # @param reducers [Array<Reducer>] reducers applied to each group
      def initialize(properties = [], reducers: [])
        super()
        @properties = Array(properties)
        @reducers = reducers
        return if @reducers.all?(Reducer)

        raise ArgumentError, "GroupBy reducers must be Valkey::Search::Reducer objects"
      end

      def to_args
        tokens = ["GROUPBY", @properties.length, *@properties]
        @reducers.each { |reducer| tokens.concat(reducer.to_args) }
        tokens
      end
    end

    # SORTBY clause: `SORTBY <nargs> <property> <ASC|DESC>... [MAX <count>]`. The
    # nargs count is the number of property/order tokens (2 per key), matching the
    # wire format and Java.
    #
    # @example
    #   Valkey::Search::SortBy.new({ "@total" => :desc }, max: 10)
    #   Valkey::Search::SortBy.new("@total", :desc)
    class SortBy < AggregateClause
      # Accepts either a single `(property, order)` pair or an ordered Hash /
      # Array-of-pairs of `property => order`.
      #
      # @param keys [String, Hash, Array] a property, or `{ property => order }`
      # @param order [Symbol] order for the single-property form (default :asc)
      # @param max [Integer, nil] emit `MAX <count>`
      def initialize(keys, order = :asc, max: nil)
        super()
        @pairs = normalize_keys(keys, order)
        @max = max
      end

      def to_args
        flat = @pairs.flat_map do |property, ord|
          [property, Search.lookup_token(Search::SORT_ORDERS, ord, "sort order")]
        end
        tokens = ["SORTBY", flat.length, *flat]
        tokens.push("MAX", @max) unless @max.nil?
        tokens
      end

      private

      def normalize_keys(keys, order)
        case keys
        when Hash then keys.to_a
        when Array
          # Array of [property, order] pairs.
          keys.map do |pair|
            unless pair.is_a?(Array) && pair.length == 2
              raise ArgumentError,
                    "SortBy Array entries must be [property, order] pairs"
            end

            pair
          end
        else [[keys, order]]
        end
      end
    end

    # FILTER clause: `FILTER <expression>`. Rows not matching the expression are
    # dropped from the pipeline.
    #
    # @example
    #   Valkey::Search::Filter.new("@total > 5")
    class Filter < AggregateClause
      # @param expression [String] the filter expression
      def initialize(expression)
        super()
        @expression = expression
      end

      def to_args
        ["FILTER", @expression]
      end
    end

    # APPLY clause: `APPLY <expression> AS <name>`. Adds a computed field to each
    # row.
    #
    # @example
    #   Valkey::Search::Apply.new("@price * @qty", as: "line_total")
    class Apply < AggregateClause
      # @param expression [String] the projection expression
      # @param as [String] result field name (required by the wire format)
      def initialize(expression, as:)
        super()
        @expression = expression
        @alias_name = as
      end

      def to_args
        ["APPLY", @expression, "AS", @alias_name]
      end
    end

    # LIMIT clause: `LIMIT <offset> <count>`. Windows the pipeline output.
    #
    # @example
    #   Valkey::Search::Limit.new(0, 10)
    class Limit < AggregateClause
      # @param offset [Integer] number of rows to skip
      # @param count [Integer] number of rows to return
      def initialize(offset, count)
        super()
        @offset = offset
        @count = count
      end

      def to_args
        ["LIMIT", @offset, @count]
      end
    end

    # Options for FT.AGGREGATE, serialized after `index query`. The ordered
    # pipeline clauses are emitted first (in supplied order), followed by the flat
    # top-level options, matching Java's builder assembly.
    #
    # Options for FT.AGGREGATE, serialized after `index query`. The flat
    # top-level options are emitted first, then the ordered pipeline clauses (in
    # supplied order).
    #
    # Note: Java emits DIALECT after the pipeline clauses; this builder emits it
    # before them. The server is order-independent for these tokens, so the
    # divergence is wire-benign — kept for a simpler assembly.
    #
    # FT.AGGREGATE does not accept the shard-scope / consistency cluster flags
    # (the server rejects them with "Unexpected: argument `ALLSHARDS`"); they are
    # available on {SearchOptions} and {InfoOptions} only.
    #
    # @example
    #   Valkey::Search::AggregateOptions.new(
    #     clauses: [
    #       Valkey::Search::GroupBy.new(["@category"],
    #         reducers: [Valkey::Search::Reducer.count(as: "total")]),
    #       Valkey::Search::SortBy.new("@total", :desc),
    #       Valkey::Search::Limit.new(0, 10),
    #     ],
    #     dialect: 2)
    #
    # @see https://valkey.io/commands/ft.aggregate/
    class AggregateOptions
      # @param clauses [Array<AggregateClause>] ordered pipeline clauses
      # @param load [Array<String>, :all, nil] LOAD fields, or :all for `LOAD *`
      # @param params [Hash, nil] query parameters (PARAMS)
      # @param verbatim [Boolean] emit VERBATIM
      # @param in_order [Boolean] emit INORDER
      # @param slop [Integer, nil] emit `SLOP <n>`
      # @param dialect [Integer, nil] emit `DIALECT <n>` (only 2 is valid)
      # @param timeout [Integer, nil] emit `TIMEOUT <ms>`
      def initialize(clauses: [], load: nil, params: nil, verbatim: false,
                     in_order: false, slop: nil, dialect: nil, timeout: nil)
        @clauses = clauses
        unless @clauses.all?(AggregateClause)
          raise ArgumentError, "aggregate clauses must be Valkey::Search::AggregateClause objects"
        end

        @load = load
        @params = params
        @verbatim = verbatim
        @in_order = in_order
        @slop = slop
        @dialect = Search.normalize_dialect(dialect)
        @timeout = timeout
      end

      # @return [Array] FT.AGGREGATE option tokens (after `index query`), in wire order
      def to_args
        args = []
        args << "VERBATIM" if @verbatim
        args << "INORDER" if @in_order
        args.push("SLOP", @slop) unless @slop.nil?
        append_load(args)
        args.push("TIMEOUT", @timeout) unless @timeout.nil?
        args.concat(Search.params_tokens(@params))
        args.push("DIALECT", @dialect) unless @dialect.nil?
        @clauses.each { |clause| args.concat(clause.to_args) }
        Search.append_cluster_flags(args, @shard_scope, @consistency)
        args
      end

      private

      def append_load(args)
        case @load
        when nil then nil
        when :all, "*" then args.push("LOAD", "*")
        when Array
          args.push("LOAD", @load.length, *@load) unless @load.empty?
        else raise ArgumentError, "load must be an Array of fields, :all, or nil"
        end
      end
    end
  end
end
