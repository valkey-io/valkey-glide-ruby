# frozen_string_literal: true

class Valkey
  module Search
    # Pagination parameters for FT.SEARCH.
    #
    # @example
    #   Valkey::Search::FtSearchLimit.new(offset: 0, count: 10)
    #
    # @see https://valkey.io/commands/ft.search/
    class FtSearchLimit
      # @return [Integer] number of results to skip
      attr_reader :offset

      # @return [Integer] maximum number of results to return
      attr_reader :count

      # @param offset [Integer] number of results to skip
      # @param count [Integer] maximum number of results to return
      def initialize(offset:, count:)
        @offset = offset
        @count = count
      end

      # @return [Array<String>]
      def to_args
        ["LIMIT", @offset.to_s, @count.to_s]
      end
    end

    # A field to include in RETURN clause of FT.SEARCH.
    #
    # @example
    #   Valkey::Search::ReturnField.new("title")
    #   Valkey::Search::ReturnField.new("$.price", field_alias: "price")
    #
    # @see https://valkey.io/commands/ft.search/
    class ReturnField
      # @return [String] field identifier
      attr_reader :field_identifier

      # @return [String, nil] optional alias for the field in results
      attr_reader :field_alias

      # @param field_identifier [String] field name to return
      # @param field_alias [String, nil] alias to rename this field in results
      def initialize(field_identifier, field_alias: nil)
        @field_identifier = field_identifier.to_s
        @field_alias = field_alias&.to_s
      end

      # @return [Array<String>]
      def to_args
        args = [@field_identifier]
        args.push("AS", @field_alias) if @field_alias
        args
      end
    end

    # Options for the FT.SEARCH command.
    #
    # All parameters are optional. Encapsulates VERBATIM, INORDER, SLOP,
    # SORTBY, WITHSORTKEYS, NOCONTENT, DIALECT, RETURN, LIMIT, PARAMS,
    # TIMEOUT, shard scope, and consistency mode.
    #
    # @example Basic pagination
    #   Valkey::Search::FtSearchOptions.new(
    #     limit: Valkey::Search::FtSearchLimit.new(offset: 0, count: 10)
    #   )
    #
    # @example Sorted search with specific fields
    #   Valkey::Search::FtSearchOptions.new(
    #     sortby: "price", sortby_order: :asc,
    #     return_fields: [
    #       Valkey::Search::ReturnField.new("title"),
    #       Valkey::Search::ReturnField.new("price")
    #     ]
    #   )
    #
    # @example Vector search with params
    #   Valkey::Search::FtSearchOptions.new(
    #     params: { "vec" => vector_bytes },
    #     dialect: 2
    #   )
    #
    # @see https://valkey.io/commands/ft.search/
    class FtSearchOptions
      # @return [Array<ReturnField>, nil] fields to return
      attr_reader :return_fields

      # @return [Integer, nil] timeout in milliseconds
      attr_reader :timeout

      # @return [Hash, nil] query parameter key/value pairs
      attr_reader :params

      # @return [FtSearchLimit, nil] pagination offset/count
      attr_reader :limit

      # @return [Boolean] return only count, not documents
      attr_reader :count

      # @return [Boolean] return only document IDs (no field content)
      attr_reader :nocontent

      # @return [Integer, nil] query dialect version (2)
      attr_reader :dialect

      # @return [Boolean] disable stemming
      attr_reader :verbatim

      # @return [Boolean] require proximity terms in order
      attr_reader :inorder

      # @return [Integer, nil] proximity slop value
      attr_reader :slop

      # @return [String, nil] field name to sort by
      attr_reader :sortby

      # @return [Symbol, nil] sort direction (:asc or :desc)
      attr_reader :sortby_order

      # @return [Boolean] include sort key values in response
      attr_reader :withsortkeys

      # @return [Symbol, nil] shard scope (:allshards or :someshards)
      attr_reader :shard_scope

      # @return [Symbol, nil] consistency mode (:consistent or :inconsistent)
      attr_reader :consistency

      # @param return_fields [Array<ReturnField>, nil] fields to include in results
      # @param timeout [Integer, nil] query timeout in milliseconds
      # @param params [Hash, nil] query parameters (for vector search, etc.)
      # @param limit [FtSearchLimit, nil] pagination
      # @param count [Boolean] return count only
      # @param nocontent [Boolean] omit field values from results
      # @param dialect [Integer, nil] query dialect (2)
      # @param verbatim [Boolean] disable stemming
      # @param inorder [Boolean] require term proximity in order
      # @param slop [Integer, nil] proximity slop
      # @param sortby [String, nil] sort field name
      # @param sortby_order [Symbol, nil] :asc or :desc
      # @param withsortkeys [Boolean] include sort key in response
      # @param shard_scope [Symbol, nil] :allshards or :someshards
      # @param consistency [Symbol, nil] :consistent or :inconsistent
      def initialize(return_fields: nil, timeout: nil, params: nil, limit: nil,
                     count: false, nocontent: false, dialect: nil,
                     verbatim: false, inorder: false, slop: nil,
                     sortby: nil, sortby_order: nil, withsortkeys: false,
                     shard_scope: nil, consistency: nil)
        @return_fields = return_fields
        @timeout = timeout
        @params = params
        @limit = limit
        @count = count
        @nocontent = nocontent
        @dialect = dialect
        @verbatim = verbatim
        @inorder = inorder
        @slop = slop
        @sortby = sortby&.to_s
        @sortby_order = sortby_order
        @withsortkeys = withsortkeys
        @shard_scope = shard_scope
        @consistency = consistency
      end

      # Serialize into the argument array appended after index and query
      # in FT.SEARCH.
      #
      # @return [Array<String>]
      def to_args
        args = []
        args << @shard_scope.to_s.upcase if @shard_scope
        args << @consistency.to_s.upcase if @consistency
        args << "NOCONTENT" if @nocontent
        args << "VERBATIM" if @verbatim
        args << "INORDER" if @inorder
        args.push("SLOP", @slop.to_s) if @slop
        if @return_fields
          return_field_args = @return_fields.flat_map(&:to_args)
          args.push("RETURN", return_field_args.size.to_s)
          args.concat(return_field_args)
        end
        if @sortby
          args.push("SORTBY", @sortby)
          args << @sortby_order.to_s.upcase if @sortby_order
        end
        args << "WITHSORTKEYS" if @withsortkeys
        args.push("TIMEOUT", @timeout.to_s) if @timeout
        if @params
          args.push("PARAMS", (@params.size * 2).to_s)
          @params.each do |name, value|
            args.push(name.to_s, value.to_s)
          end
        end
        args.concat(@limit.to_args) if @limit
        args << "COUNT" if @count
        args.push("DIALECT", @dialect.to_s) if @dialect
        args
      end
    end
  end
end
