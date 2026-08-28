# frozen_string_literal: true

class Valkey
  module Search
    # Options for FT.SEARCH, serialized after `index query`. Mirrors Java
    # FTSearchOptions.
    #
    # @example
    #   Valkey::Search::SearchOptions.new(limit: { offset: 0, count: 10 },
    #     return_fields: ["title", { name: "loc", as: "location" }], dialect: 2)
    #
    # @see https://redis.io/commands/ft.search/
    class SearchOptions
      # @return [Boolean] NOCONTENT requested (the parser needs this)
      attr_reader :no_content
      # @return [Boolean] WITHSORTKEYS requested (the parser needs this)
      attr_reader :with_sort_keys

      # @param limit [Hash, Array, nil] { offset:, count: } or [offset, count]
      # @param return_fields [Array, nil] field name String/Symbol or { name:, as: } Hash
      # @param params [Hash, nil] query parameters (PARAMS)
      # @param sort_by [String, nil] field to sort by
      # @param sort_order [Symbol] :asc (default) or :desc
      # @param shard_scope [Symbol, nil] :all_shards or :some_shards
      # @param consistency [Symbol, nil] :consistent or :inconsistent
      def initialize(limit: nil, return_fields: nil, params: nil, sort_by: nil,
                     sort_order: :asc, with_sort_keys: false, no_content: false,
                     verbatim: false, in_order: false, slop: nil, dialect: nil,
                     timeout: nil, shard_scope: nil, consistency: nil)
        raise ArgumentError, "with_sort_keys requires sort_by" if with_sort_keys && sort_by.nil?

        @limit = normalize_limit(limit)
        @return_tokens = expand_return_fields(return_fields)
        @params = params
        @sort_by = sort_by
        @sort_order = Search.lookup_token(Search::SORT_ORDERS, sort_order, "sort order")
        @with_sort_keys = with_sort_keys
        @no_content = no_content
        @verbatim = verbatim
        @in_order = in_order
        @slop = slop
        @dialect = Search.normalize_dialect(dialect)
        @timeout = timeout
        @shard_scope = shard_scope.nil? ? nil : Search.lookup_token(Search::SHARD_SCOPES, shard_scope, "shard scope")
        @consistency = consistency.nil? ? nil : Search.lookup_token(Search::CONSISTENCY, consistency, "consistency")
      end

      # @return [Array] FT.SEARCH option tokens (after `index query`), in wire order
      def to_args
        args = []
        args << "NOCONTENT" if @no_content
        args << "VERBATIM" if @verbatim
        args << "INORDER" if @in_order
        args.push("SLOP", @slop) unless @slop.nil?
        args.push("LIMIT", @limit[0], @limit[1]) unless @limit.nil?
        args.push("RETURN", @return_tokens.length, *@return_tokens) if @return_tokens && !@return_tokens.empty?
        append_sort_by(args)
        args << "WITHSORTKEYS" if @with_sort_keys
        args.concat(Search.params_tokens(@params))
        args.push("DIALECT", @dialect) unless @dialect.nil?
        args.push("TIMEOUT", @timeout) unless @timeout.nil?
        Search.append_cluster_flags(args, @shard_scope, @consistency)
        args
      end

      private

      # RETURN count is the number of tokens that follow (identifier + optional
      # `AS alias`), matching Java. Each entry is a field name (String or Symbol)
      # or a Hash naming the field and an optional alias. The Hash accepts either
      # Symbol keys (`{ name:, as: }`) or the String keys `"name"`/`"as"`.
      def expand_return_fields(return_fields)
        return nil if return_fields.nil?

        return_fields.flat_map do |field|
          case field
          when String, Symbol
            [field.to_s]
          when Hash
            name = field[:name] || field["name"] or raise ArgumentError, "return field Hash requires :name"
            as = field[:as] || field["as"]
            as ? [name, "AS", as] : [name]
          else
            raise ArgumentError, "return field must be a String, Symbol, or { name:, as: } Hash, got #{field.class}"
          end
        end
      end

      def append_sort_by(args)
        return if @sort_by.nil?

        args.push("SORTBY", @sort_by, @sort_order)
      end

      def normalize_limit(limit)
        case limit
        when nil then nil
        when Array
          raise ArgumentError, "limit Array must be [offset, count], got #{limit.inspect}" unless limit.length == 2

          limit
        when Hash then [limit.fetch(:offset), limit.fetch(:count)]
        else raise ArgumentError, "limit must be a { offset:, count: } Hash or [offset, count] Array"
        end
      end
    end

    # Structured FT.SEARCH result: a total count plus a list of documents. The
    # raw-args path still returns the unwrapped reply. Mirrors Go/C#.
    #
    # @see https://redis.io/commands/ft.search/
    class SearchResult
      Document = Struct.new(:key, :fields, :sort_key)

      # @return [Integer] total matching documents
      attr_reader :total_results
      # @return [Array<Document>] returned documents
      attr_reader :documents

      def initialize(total_results, documents)
        @total_results = total_results
        @documents = documents
      end

      # Parse a raw FT.SEARCH reply. Handles both the GLIDE normalized map form
      # ([count, { key => { field => value } }]) and the flat RESP2 array form,
      # honoring no_content and with_sort_keys.
      #
      # @return [SearchResult]
      def self.from_raw(raw, no_content: false, with_sort_keys: false)
        return new(0, []) if raw.nil? || raw.empty?

        total = coerce_count(raw[0])
        rest = raw[1..] || []
        documents =
          if rest.length == 1 && rest[0].is_a?(Hash)
            parse_map(rest[0], no_content: no_content, with_sort_keys: with_sort_keys)
          else
            parse_flat(rest, no_content: no_content, with_sort_keys: with_sort_keys)
          end
        new(total, documents)
      end

      # coerce the count strictly so a malformed reply
      # surfaces loudly instead of silently becoming "0 results". Only an Integer
      # or an integer-valued String is accepted — a Float (e.g. 2.5) is rejected
      # rather than silently truncated by Integer().
      def self.coerce_count(value)
        unless value.is_a?(Integer) || value.is_a?(String)
          raise TypeError, "FT.SEARCH reply had a non-integer count: #{value.inspect}"
        end

        Integer(value)
      rescue ArgumentError, TypeError
        raise TypeError, "FT.SEARCH reply had a non-integer count: #{value.inspect}"
      end

      # GLIDE normalized map form: { key => value }. With content, value is the
      # field map; under WITHSORTKEYS it is [sort_key, field_map]; under
      # WITHSORTKEYS + NOCONTENT it is the bare sort key (no field map); under
      # NOCONTENT alone it may be nil/empty.
      def self.parse_map(map, no_content:, with_sort_keys:)
        map.map do |key, value|
          sort_key = nil
          fields = {}
          if with_sort_keys && value.is_a?(Array)
            sort_key = value[0]
            fields = value[1] if value[1].is_a?(Hash)
          elsif with_sort_keys && no_content
            # WITHSORTKEYS + NOCONTENT — the value is the bare sort key,
            # neither an Array nor a field Hash, so capture it directly.
            sort_key = value
          elsif !no_content && value.is_a?(Hash)
            fields = value
          end
          Document.new(key, fields, sort_key)
        end
      end

      def self.parse_flat(rest, no_content:, with_sort_keys:)
        documents = []
        i = 0
        while i < rest.length
          key = rest[i]
          i += 1
          sort_key = nil
          if with_sort_keys
            # bounds-check every read past the KEY so a truncated reply
            # raises loudly (matching coerce_count) instead of emitting a phantom
            # document with missing pieces.
            raise TypeError, "FT.SEARCH reply truncated (missing sort key)" if i >= rest.length

            sort_key = rest[i]
            i += 1
          end
          fields = {}
          unless no_content
            raise TypeError, "FT.SEARCH reply truncated (missing field payload)" if i >= rest.length

            pairs = rest[i]
            i += 1
            # block-form to_h tolerates an odd-length array (dangling key => nil),
            # unlike bare each_slice(2).to_h which raises, so a malformed reply never
            # escapes ft_search as a non-Valkey error.
            fields = pairs.each_slice(2).to_h { |k, v| [k, v] } if pairs.is_a?(Array)
          end
          documents << Document.new(key, fields, sort_key)
        end
        documents
      end
      private_class_method :parse_map, :parse_flat, :coerce_count
    end
  end
end
