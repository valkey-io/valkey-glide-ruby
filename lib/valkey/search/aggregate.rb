# frozen_string_literal: true

class Valkey
  # Pipeline clauses and options for FT.AGGREGATE. Clauses (GroupBy, SortBy,
  # Filter, Limit, Apply) serialize in the order the user supplies them, since
  # FT.AGGREGATE is an ordered pipeline. Flat top-level options (verbatim, load,
  # params, dialect, timeout) are keyword arguments on {AggregateOptions}.
  #
  # @see https://valkey.io/commands/ft.aggregate/
  module Search
    # A single REDUCE within a GROUPBY. Emits `REDUCE <function> <nargs> <arg...>
    # [AS <name>]`. The nargs count is the number of argument tokens that follow
    # the function name.
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

      # @param [String, Symbol] function - reducer function name
      # @param [Array] args - argument tokens following the function
      # @param [String, nil] as - optional AS alias
      def initialize(function, *args, as: nil)
        @function = function.to_s.upcase
        @args = args
        @alias_name = as
      end

      # COUNT reducer for the number of records in the group. Takes no property.
      #
      # @param [String, nil] as - optional AS alias
      #
      # @return [Reducer] the configured reducer
      def self.count(as: nil)
        new("COUNT", as: as)
      end

      # TOLIST — collects all values for +property+ across the records in a
      # group into a single array, removing duplicates and nil values. If a
      # value is itself an array, it is flattened one level before being
      # added. Values are returned in the order they were first encountered
      # (valkey-search 1.3.0, #932).
      #
      # @example
      #   Valkey::Search::Reducer.to_list("@color", as: "colors")
      #
      # @param [String] property - the property whose values are collected
      # @param [String, nil] as - optional AS alias
      def self.to_list(property, as: nil)
        new("TOLIST", property, as: as)
      end

      # FIRST_VALUE — returns the value of +property+ from a single record
      # in the group. Without +by+, the first record encountered wins. With
      # +by+, the record whose +by+ property is smallest (+order: :asc+,
      # the default) or largest (+order: :desc+) wins; ties keep the
      # first-encountered record (valkey-search 1.3.0, #946).
      #
      # @example
      #   Valkey::Search::Reducer.first_value("@title", as: "any_title")
      #   Valkey::Search::Reducer.first_value("@title", by: "@price", order: :desc, as: "most_expensive_title")
      #
      # @param [String] property - the property whose value is returned
      # @param [String, nil] by - the property used to choose the winning
      #   record. Required if +order+ is given.
      # @param [Symbol, nil] order - :asc (default on the server when +by+ is
      #   set without +order+) or :desc
      # @param [String, nil] as - optional AS alias
      #
      # @raise [ArgumentError] if +order+ is given without +by+
      def self.first_value(property, by: nil, order: nil, as: nil)
        raise ArgumentError, "first_value: order requires by to be set" if !order.nil? && by.nil?

        args = [property]
        unless by.nil?
          args.push("BY", by)
          args.push(Search.lookup_token(Search::SORT_ORDERS, order, "sort order")) unless order.nil?
        end
        new("FIRST_VALUE", *args, as: as)
      end

      # RANDOM_SAMPLE — returns a uniform random sample of up to +size+
      # values of +property+ from the records in a group, using reservoir
      # sampling (valkey-search 1.3.0, #949).
      #
      # @example
      #   Valkey::Search::Reducer.random_sample("@score", 5, as: "score_sample")
      #
      # @param [String] property - the property to sample values from
      # @param [Integer] size - the maximum number of values to sample. Must
      #   be a non-negative integer no greater than 1000; the server
      #   rejects values outside this range.
      # @param [String, nil] as - optional AS alias
      def self.random_sample(property, size, as: nil)
        new("RANDOM_SAMPLE", property, size.to_s, as: as)
      end

      # Defines Reducer.count_distinct/.sum/.min/.max/.avg/.stddev, each taking a
      # single property, from {Search::REDUCER_FUNCTIONS} (skipping COUNT, which
      # takes no property and is defined explicitly above). One definition per
      # function name keeps the class methods, and their docs, from drifting out
      # of sync with the table.
      (Search::REDUCER_FUNCTIONS - %w[COUNT]).each do |function|
        define_singleton_method(function.downcase) do |property, as: nil|
          new(function, property, as: as)
        end
      end

      # @return [Array] `REDUCE <function> <nargs> <arg...> [AS <name>]`
      def to_args
        tokens = ["REDUCE", @function, @args.length, *@args]
        tokens.push("AS", @alias_name) unless @alias_name.nil?
        tokens
      end
    end

    # Base class for an aggregate pipeline clause. Subclasses implement #to_args.
    #
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
      # @param [Array<String>] properties - grouping properties (may be empty for a
      #   global aggregation, matching `GROUPBY 0`)
      # @param [Array<Reducer>] reducers - reducers applied to each group
      def initialize(properties = [], reducers: [])
        super()
        @properties = Array(properties)
        @reducers = Array(reducers)
        return if @reducers.all?(Reducer)

        raise ArgumentError, "GroupBy reducers must be Valkey::Search::Reducer objects"
      end

      # Serialize the GROUPBY clause and its reducers.
      #
      # @return [Array] the GROUPBY clause tokens
      def to_args
        tokens = ["GROUPBY", @properties.length, *@properties]
        @reducers.each { |reducer| tokens.concat(reducer.to_args) }
        tokens
      end
    end

    # SORTBY clause: `SORTBY <nargs> <property> <ASC|DESC>... [MAX <count>]`. The
    # nargs count is the number of property/order tokens (2 per key).
    #
    # Accepts an ordered Hash of `property => order` for multiple sort keys, since
    # insertion order determines sort priority and Ruby Hashes preserve it.
    #
    # @example
    #   Valkey::Search::SortBy.new({ "@total" => :desc }, max: 10)
    #   Valkey::Search::SortBy.new("@total", :desc)
    class SortBy < AggregateClause
      # Accepts either a single `(property, order)` pair or an ordered Hash /
      # Array-of-pairs of `property => order`.
      #
      # @param [String, Hash, Array] keys - a property, or `{ property => order }`
      # @param [Symbol] order - order for the single-property form (default :asc)
      # @param [Integer, nil] max - emit `MAX <count>`
      def initialize(keys, order = :asc, max: nil)
        super()
        @pairs = normalize_keys(keys, order)
        @max = max
      end

      # Serialize the SORTBY clause.
      #
      # @return [Array] the SORTBY clause tokens
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
      # @param [String] expression - the filter expression
      def initialize(expression)
        super()
        @expression = expression
      end

      # Serialize the FILTER clause.
      #
      # @return [Array] the FILTER clause tokens
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
      # @param [String] expression - the projection expression
      # @param [String] as - result field name (APPLY requires the AS clause)
      def initialize(expression, as:)
        super()
        @expression = expression
        @alias_name = as
      end

      # Serialize the APPLY clause.
      #
      # @return [Array] the APPLY clause tokens
      def to_args
        ["APPLY", @expression, "AS", @alias_name]
      end
    end

    # LIMIT clause: `LIMIT <offset> <count>`. Windows the pipeline output.
    #
    # @example
    #   Valkey::Search::Limit.new(0, 10)
    class Limit < AggregateClause
      # @param [Integer] offset - number of rows to skip
      # @param [Integer] count - number of rows to return
      def initialize(offset, count)
        super()
        @offset = offset
        @count = count
      end

      # Serialize the LIMIT clause.
      #
      # @return [Array] the LIMIT clause tokens
      def to_args
        ["LIMIT", @offset, @count]
      end
    end

    # Options for FT.AGGREGATE, serialized after `index query`. The flat
    # top-level options are emitted first, then the ordered pipeline clauses (in
    # supplied order).
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
      attr_reader :with_cursor

      # @param [Array<AggregateClause>] clauses - ordered pipeline clauses
      # @param [Array<String, LoadField>, :all, nil] load - LOAD fields
      #   (plain field identifiers and/or {LoadField} entries to rename via
      #   AS — valkey-search 1.3.0; see {LoadField}'s docs for the
      #   compatibility gate), or :all for `LOAD *`
      # @param [Hash, nil] params - query parameters (PARAMS)
      # @param [Boolean] verbatim - emit VERBATIM
      # @param [Boolean] in_order - emit INORDER
      # @param [Integer, nil] slop - emit `SLOP <n>`
      # @param [Integer, nil] dialect - emit `DIALECT <n>` (only 2 is valid)
      # @param [Integer, nil] timeout - emit `TIMEOUT <ms>`
      # @param [Boolean] add_scores - exposes the relevance score as a
      #   pipeline field named `__score` (valkey-search 1.3.0). `__score`
      #   can then be referenced like any other pipeline field in a
      #   {LoadField}, {Apply} expression, or a {SortBy} key.
      # @param [String, nil] scorer - the scoring function used to compute
      #   `__score` (valkey-search 1.3.0). `"BM25STD"` is currently the only
      #   registered value. Has no visible effect unless combined with
      #   `add_scores: true` (or inspected indirectly via a SORTBY on `__score`).
      # @param [WithCursor, nil] with_cursor - requests a paged reply instead
      #   of the whole result set at once. The reply shape becomes a
      #   two-element array of `[rows, cursor_id]`. A paged query, and every
      #   subsequent {Valkey::Commands::VectorSearchCommands#ft_cursor_read}/`#ft_cursor_del`
      #   against the cursor it opens, always reads from the PRIMARY of the
      #   index's slot regardless of ReadFrom — a cursor is a
      #   per-process, node-local server resource. A plain aggregate without
      #   `with_cursor` is unaffected and still prefers replicas as normal.
      def initialize(clauses: nil, load: nil, params: nil, verbatim: false,
                     in_order: false, slop: nil, dialect: nil, timeout: nil,
                     add_scores: false, scorer: nil, with_cursor: nil)
        @clauses = clauses || []
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
        @add_scores = add_scores
        @scorer = scorer
        @with_cursor = with_cursor
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
        args << "ADDSCORES" if @add_scores
        args.push("SCORER", @scorer) unless @scorer.nil?
        args.concat(@with_cursor.to_args) unless @with_cursor.nil?
        args
      end

      private

      def append_load(args)
        case @load
        when nil then nil
        when :all, "*" then args.push("LOAD", "*")
        when Array
          args.concat(Search.load_fields_to_args(@load))
        else raise ArgumentError, "load must be an Array of fields/LoadField, :all, or nil"
        end
      end
    end
  end
end
