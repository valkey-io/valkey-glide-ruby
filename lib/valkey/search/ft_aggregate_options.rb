# frozen_string_literal: true

class Valkey
  module Search
    # A reducer function used within a {GroupBy} clause.
    #
    # @example
    #   Valkey::Search::Reducer.new("SUM", ["@price"], name: "total")
    #   Valkey::Search::Reducer.new("COUNT", [], name: "count")
    #
    # @see https://valkey.io/commands/ft.aggregate/
    class Reducer
      # @return [String] the reduction function (COUNT, SUM, AVG, MIN, MAX, etc.)
      attr_reader :function

      # @return [Array<String>] arguments for the reducer
      attr_reader :args

      # @return [String, nil] alias for the reduced value
      attr_reader :name

      # @param function [String] reduction function name
      # @param args [Array<String>] reducer arguments (field references, etc.)
      # @param name [String, nil] output property name (AS alias)
      def initialize(function, args = [], name: nil)
        @function = function.to_s.upcase
        @args = args.map(&:to_s)
        @name = name&.to_s
      end

      # @return [Array<String>]
      def to_args
        result = ["REDUCE", @function, @args.size.to_s]
        result.concat(@args)
        result.push("AS", @name) if @name
        result
      end
    end

    # GROUPBY pipeline clause for FT.AGGREGATE.
    #
    # @example
    #   Valkey::Search::GroupBy.new(["@category"],
    #     reducers: [Valkey::Search::Reducer.new("COUNT", [], name: "count")])
    #
    # @see https://valkey.io/commands/ft.aggregate/
    class GroupBy
      # @return [Array<String>] properties to group by
      attr_reader :properties

      # @return [Array<Reducer>] reducers applied to each group
      attr_reader :reducers

      # @param properties [Array<String>] field names to group by
      # @param reducers [Array<Reducer>] reducer functions
      def initialize(properties, reducers: [])
        @properties = properties.map(&:to_s)
        @reducers = reducers
      end

      # @return [Array<String>]
      def to_args
        args = ["GROUPBY", @properties.size.to_s]
        args.concat(@properties)
        @reducers.each { |r| args.concat(r.to_args) }
        args
      end
    end

    # A single sort property within a {SortBy} clause.
    #
    # @example
    #   Valkey::Search::SortProperty.new("@price", :asc)
    #
    class SortProperty
      # @return [String] property name
      attr_reader :property

      # @return [Symbol] sort direction (:asc or :desc)
      attr_reader :order

      # @param property [String] field name to sort by
      # @param order [Symbol, String] :asc or :desc
      def initialize(property, order)
        @property = property.to_s
        @order = order.to_s.upcase.to_sym
      end

      # @return [Array<String>]
      def to_args
        [@property, @order.to_s]
      end
    end

    # SORTBY pipeline clause for FT.AGGREGATE.
    #
    # @example
    #   Valkey::Search::SortBy.new(
    #     [Valkey::Search::SortProperty.new("@price", :asc)],
    #     max: 10
    #   )
    #
    # @see https://valkey.io/commands/ft.aggregate/
    class SortBy
      # @return [Array<SortProperty>] sort properties
      attr_reader :properties

      # @return [Integer, nil] MAX optimization hint
      attr_reader :max

      # @param properties [Array<SortProperty>] sort criteria
      # @param max [Integer, nil] optimization: only sort top N elements
      def initialize(properties, max: nil)
        @properties = properties
        @max = max
      end

      # @return [Array<String>]
      def to_args
        args = ["SORTBY", (@properties.size * 2).to_s]
        @properties.each { |p| args.concat(p.to_args) }
        args.push("MAX", @max.to_s) if @max
        args
      end
    end

    # APPLY pipeline clause for FT.AGGREGATE.
    #
    # @example
    #   Valkey::Search::Apply.new("@price * 1.1", name: "price_with_tax")
    #
    # @see https://valkey.io/commands/ft.aggregate/
    class Apply
      # @return [String] the transformation expression
      attr_reader :expression

      # @return [String] output property name
      attr_reader :name

      # @param expression [String] transformation expression
      # @param name [String] output property alias
      def initialize(expression, name:)
        @expression = expression.to_s
        @name = name.to_s
      end

      # @return [Array<String>]
      def to_args
        ["APPLY", @expression, "AS", @name]
      end
    end

    # FILTER pipeline clause for FT.AGGREGATE.
    #
    # @example
    #   Valkey::Search::Filter.new("@count > 5")
    #
    # @see https://valkey.io/commands/ft.aggregate/
    class Filter
      # @return [String] filter expression
      attr_reader :expression

      # @param expression [String] predicate expression
      def initialize(expression)
        @expression = expression.to_s
      end

      # @return [Array<String>]
      def to_args
        ["FILTER", @expression]
      end
    end

    # LIMIT pipeline clause for FT.AGGREGATE.
    #
    # @example
    #   Valkey::Search::AggregateLimit.new(offset: 0, count: 10)
    #
    # @see https://valkey.io/commands/ft.aggregate/
    class AggregateLimit
      # @return [Integer] number of records to skip
      attr_reader :offset

      # @return [Integer] max records to retain
      attr_reader :count

      # @param offset [Integer] starting point
      # @param count [Integer] number of records
      def initialize(offset:, count:)
        @offset = offset
        @count = count
      end

      # @return [Array<String>]
      def to_args
        ["LIMIT", @offset.to_s, @count.to_s]
      end
    end

    # Options for the FT.AGGREGATE command.
    #
    # Encapsulates query-level options (VERBATIM, INORDER, SLOP, LOAD, TIMEOUT,
    # PARAMS, DIALECT) and pipeline clauses (GROUPBY, SORTBY, APPLY, FILTER, LIMIT)
    # which can be repeated and intermixed in any order.
    #
    # @example Basic aggregation
    #   Valkey::Search::FtAggregateOptions.new(
    #     load_fields: ["@price"],
    #     clauses: [
    #       Valkey::Search::GroupBy.new(["@category"],
    #         reducers: [Valkey::Search::Reducer.new("SUM", ["@price"], name: "total")])
    #     ]
    #   )
    #
    # @example With sorting and limit
    #   Valkey::Search::FtAggregateOptions.new(
    #     clauses: [
    #       Valkey::Search::GroupBy.new(["@category"],
    #         reducers: [Valkey::Search::Reducer.new("COUNT", [], name: "count")]),
    #       Valkey::Search::SortBy.new(
    #         [Valkey::Search::SortProperty.new("@count", :desc)], max: 5),
    #       Valkey::Search::AggregateLimit.new(offset: 0, count: 5)
    #     ]
    #   )
    #
    # @see https://valkey.io/commands/ft.aggregate/
    class FtAggregateOptions
      # @return [Boolean] load all indexed fields
      attr_reader :load_all

      # @return [Array<String>] specific fields to load
      attr_reader :load_fields

      # @return [Integer, nil] timeout in milliseconds
      attr_reader :timeout

      # @return [Hash, nil] query parameter key/value pairs
      attr_reader :params

      # @return [Array] pipeline clauses (GroupBy, SortBy, Apply, Filter, AggregateLimit)
      attr_reader :clauses

      # @return [Boolean] disable stemming
      attr_reader :verbatim

      # @return [Boolean] require proximity terms in order
      attr_reader :inorder

      # @return [Integer, nil] proximity slop value
      attr_reader :slop

      # @return [Integer, nil] query dialect version
      attr_reader :dialect

      # @param load_all [Boolean] load all indexed fields for reducers
      # @param load_fields [Array<String>] specific fields to load for reducers
      # @param timeout [Integer, nil] query timeout in milliseconds
      # @param params [Hash, nil] query parameters
      # @param clauses [Array] pipeline clauses in execution order
      # @param verbatim [Boolean] disable stemming
      # @param inorder [Boolean] require term proximity in order
      # @param slop [Integer, nil] proximity slop
      # @param dialect [Integer, nil] query dialect (2)
      def initialize(load_all: false, load_fields: [], timeout: nil, params: nil,
                     clauses: [], verbatim: false, inorder: false, slop: nil,
                     dialect: nil)
        @load_all = load_all
        @load_fields = load_fields.map(&:to_s)
        @timeout = timeout
        @params = params
        @clauses = clauses
        @verbatim = verbatim
        @inorder = inorder
        @slop = slop
        @dialect = dialect
      end

      # Serialize into the argument array appended after index and query
      # in FT.AGGREGATE.
      #
      # @return [Array<String>]
      def to_args
        args = []
        args << "VERBATIM" if @verbatim
        args << "INORDER" if @inorder
        args.push("SLOP", @slop.to_s) if @slop
        if @load_all
          args.push("LOAD", "*")
        elsif @load_fields.any?
          args.push("LOAD", @load_fields.size.to_s)
          args.concat(@load_fields)
        end
        args.push("TIMEOUT", @timeout.to_s) if @timeout
        if @params && !@params.empty?
          args.push("PARAMS", (@params.size * 2).to_s)
          @params.each do |name, value|
            args.push(name.to_s, value.to_s)
          end
        end
        @clauses.each { |clause| args.concat(clause.to_args) }
        args.push("DIALECT", @dialect.to_s) if @dialect
        args
      end
    end
  end
end
