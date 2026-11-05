# frozen_string_literal: true

require "securerandom"

class Valkey
  module Search
    # Keywords used by the FT.HYBRID command (distinct names from
    # FT.AGGREGATE where the server registers separate tokens, e.g. SCORER
    # has the same text but COMBINE/SEARCH/VSIM are HYBRID-only).
    module HybridKeywords
      SEARCH = "SEARCH"
      VSIM = "VSIM"
      SCORER = "SCORER"
      YIELD_SCORE_AS = "YIELD_SCORE_AS"
      KNN = "KNN"
      K = "K"
      EF_RUNTIME = "EF_RUNTIME"
      SHARD_K_RATIO = "SHARD_K_RATIO"
      FILTER = "FILTER"
      POLICY = "POLICY"
      BATCH_SIZE = "BATCH_SIZE"
      COMBINE = "COMBINE"
      RRF = "RRF"
      LINEAR = "LINEAR"
      FUNCTION = "FUNCTION"
      CONSTANT = "CONSTANT"
      WINDOW = "WINDOW"
      ALPHA = "ALPHA"
      BETA = "BETA"
      EXPR = "EXPR"
      LOCALONLY = "LOCALONLY"
      PARAMS = "PARAMS"
      DIALECT = "DIALECT"
      TIMEOUT = "TIMEOUT"
    end

    # Controls how a VSIM pre-filter ({HybridVsimFilter}) is applied against
    # the vector search. Only meaningful inside a *counted* VSIM FILTER block
    # — valkey-search's uncounted `FILTER <expr>` extension on VSIM (no
    # leading token count) cannot carry a policy at all; the server requires
    # the counted form to accept POLICY/BATCH_SIZE.
    module HybridFilterPolicy
      ADHOC = "ADHOC"
      BATCHES = "BATCHES"
    end

    # A pre-filter on the VSIM arm's vector search, written in the same query
    # language the SEARCH arm uses (e.g. `@title:hello`).
    #
    # @example
    #   Valkey::Search::HybridVsimFilter.new("@title:hello")
    #   Valkey::Search::HybridVsimFilter.new("@title:hello",
    #     policy: Valkey::Search::HybridFilterPolicy::BATCHES, batch_size: 50)
    class HybridVsimFilter
      attr_reader :expression, :policy, :batch_size

      # @param expression [String] the filter expression
      # @param policy [String, nil] one of {HybridFilterPolicy}; forces the
      #   wire-level counted VSIM FILTER form (required for the server to
      #   recognize POLICY at all)
      # @param batch_size [Integer, nil] requires `policy: HybridFilterPolicy::BATCHES`
      # @raise [ArgumentError] if batch_size is set without policy BATCHES
      def initialize(expression, policy: nil, batch_size: nil)
        if !batch_size.nil? && policy != HybridFilterPolicy::BATCHES
          raise ArgumentError, "batch_size requires policy: Valkey::Search::HybridFilterPolicy::BATCHES"
        end

        @expression = expression
        @policy = policy
        @batch_size = batch_size
      end

      # @return [Array] the FILTER clause tokens — counted form when policy
      #   or batch_size is set, the uncounted extension form otherwise
      def to_args
        sub_args = []
        sub_args.push(HybridKeywords::POLICY, @policy) unless @policy.nil?
        sub_args.push(HybridKeywords::BATCH_SIZE, @batch_size) unless @batch_size.nil?
        return [HybridKeywords::FILTER, @expression] if sub_args.empty?

        [HybridKeywords::FILTER, 1 + sub_args.length, @expression, *sub_args]
      end
    end

    # The SEARCH arm of an FT.HYBRID query: an ordinary (non-vector)
    # FT.SEARCH-style text/tag/numeric query, run alongside the VSIM arm and
    # fused with it. A vector query (e.g. a `=>[KNN ...]` clause) is rejected
    # by the server here — use {HybridVsimArm} for the vector half instead.
    #
    # @example
    #   Valkey::Search::HybridSearchArm.new("hello world", yield_score_as: "ss")
    class HybridSearchArm
      attr_reader :query, :scorer, :yield_score_as

      # @param query [String] the text/tag/numeric query
      # @param scorer [String, nil] the scoring function ("BM25STD" is
      #   currently the only registered value)
      # @param yield_score_as [String, nil] exposes this arm's score under
      #   the given column name
      def initialize(query, scorer: nil, yield_score_as: nil)
        @query = query
        @scorer = scorer
        @yield_score_as = yield_score_as
      end

      # @return [Array] the SEARCH clause tokens
      def to_args
        args = [HybridKeywords::SEARCH, @query]
        args.push(HybridKeywords::SCORER, @scorer) unless @scorer.nil?
        args.push(HybridKeywords::YIELD_SCORE_AS, @yield_score_as) unless @yield_score_as.nil?
        args
      end
    end

    # The VSIM arm of an FT.HYBRID query: a vector similarity search against
    # a vector field, run alongside the SEARCH arm and fused with it.
    #
    # The query vector can be given two ways:
    # - As raw bytes (any binary-encoded String, or any non-binary String
    #   not starting with `$`): the client generates an internal
    #   `$`-prefixed PARAMS entry and references it on the wire. FT.HYBRID's
    #   VSIM clause has no wire-level inline vector literal — the parameter
    #   token must start with `$` or the server rejects it ("VSIM: vector
    #   parameter must start with '$'").
    # - As an explicit `$name` String (non-binary encoding): the caller
    #   manages their own entry in {HybridOptions#params}.
    #
    # The decision is made by Ruby type/encoding, never by the vector's
    # leading byte — see {#param_reference?}. A binary-encoded
    # (`String#b`/ASCII-8BIT) vector is always raw vector data, even if it
    # happens to start with the byte `0x24` ("$"); callers passing raw
    # vector bytes should use `.b` so the encoding alone disambiguates
    # them from an intentional `$name` reference, matching Python/Go's
    # bytes-vs-string distinction as closely as Ruby's single String type
    # allows.
    #
    # @example
    #   Valkey::Search::HybridVsimArm.new("vec", query_vector_bytes, k: 10)
    class HybridVsimArm
      attr_reader :field, :vector, :k, :ef_runtime, :shard_k_ratio, :yield_score_as, :filter

      # @param field [String] the vector field's identifier, without the
      #   leading `@` (added automatically)
      # @param vector [String] the query vector as raw bytes, or an explicit
      #   `$name` reference String
      # @param k [Integer, nil] nearest neighbours to return. Omitting the
      #   whole KNN block (k, ef_runtime and shard_k_ratio all nil) defaults
      #   to 10 server-side.
      # @param ef_runtime [Integer, nil] HNSW search-time effort parameter.
      #   Only valid when the KNN block is written.
      # @param shard_k_ratio [Float, nil] tunes per-shard fanout work
      # @param yield_score_as [String, nil] exposes this arm's score (vector
      #   distance) under the given column name
      # @param filter [HybridVsimFilter, nil] a pre-filter on the vector search
      # @raise [ArgumentError] if ef_runtime is set while filter.policy is
      #   HybridFilterPolicy::ADHOC (the server rejects that combination:
      #   "EF_RUNTIME is irrelevant for POLICY ADHOC")
      def initialize(field, vector, k: nil, ef_runtime: nil, shard_k_ratio: nil, yield_score_as: nil, filter: nil)
        if !ef_runtime.nil? && !filter.nil? && filter.policy == HybridFilterPolicy::ADHOC
          raise ArgumentError,
                "ef_runtime is not supported with filter.policy: HybridFilterPolicy::ADHOC " \
                "(the server rejects this combination: \"EF_RUNTIME is irrelevant for POLICY ADHOC\")"
        end

        @field = field
        @vector = vector
        @k = k
        @ef_runtime = ef_runtime
        @shard_k_ratio = shard_k_ratio
        @yield_score_as = yield_score_as
        @filter = filter
      end

      # @return [Boolean] true if +vector+ is a `$name` parameter reference
      #   rather than raw vector bytes requiring a generated PARAMS entry.
      #   Decided by Ruby type/encoding, never by the vector's leading
      #   byte: a binary-encoded (ASCII-8BIT) String is always raw vector
      #   data, even when its first byte happens to be `0x24` ("$") —
      #   matching Python/Go's bytes-vs-string distinction (the port rule
      #   "param reference by type, not by leading byte"). Only a String
      #   whose encoding is NOT binary AND that starts with `$` counts as
      #   a reference.
      def param_reference?
        @vector.is_a?(String) && @vector.encoding != Encoding::ASCII_8BIT && @vector.start_with?("$")
      end

      # @param generated_param_name [String, nil] the `$`-prefixed name to
      #   reference when +vector+ is raw bytes rather than an explicit
      #   `$name` String. Supplied by {Valkey::Commands::VectorSearchCommands#ft_hybrid}.
      # @return [Array] the VSIM clause tokens
      # @raise [ArgumentError] if vector is raw bytes and no generated name was supplied
      def to_args(generated_param_name: nil)
        param_ref =
          if param_reference?
            @vector
          else
            if generated_param_name.nil?
              raise ArgumentError,
                    "generated_param_name is required when vector is raw bytes"
            end

            generated_param_name
          end
        field_ref = "@#{@field}"
        args = [HybridKeywords::VSIM, field_ref, param_ref]
        knn_sub_args = []
        knn_sub_args.push(HybridKeywords::K, @k) unless @k.nil?
        knn_sub_args.push(HybridKeywords::EF_RUNTIME, @ef_runtime) unless @ef_runtime.nil?
        knn_sub_args.push(HybridKeywords::SHARD_K_RATIO, @shard_k_ratio) unless @shard_k_ratio.nil?
        args.push(HybridKeywords::KNN, knn_sub_args.length, *knn_sub_args) unless knn_sub_args.empty?
        args.push(HybridKeywords::YIELD_SCORE_AS, @yield_score_as) unless @yield_score_as.nil?
        args.concat(@filter.to_args) unless @filter.nil?
        args
      end
    end

    # Abstract base for the COMBINE clause of FT.HYBRID, controlling how the
    # SEARCH and VSIM arms' per-document scores are fused into one ranking.
    # See {HybridCombine.rrf}, {HybridCombine.linear}, {HybridCombine.function}.
    # @abstract
    class HybridCombine
      # @return [Array] the COMBINE clause tokens
      def to_args
        raise NotImplementedError, "#{self.class} must implement #to_args"
      end

      # Fuses the two arms' results using Reciprocal Rank Fusion: each arm's
      # rank (not its raw score) contributes `1 / (constant + rank)`.
      #
      # @param constant [Float, nil] must be non-negative (a negative value
      #   is rejected server-side — it places a pole at rank == -constant)
      # @param window [Integer, nil] how many of each arm's results take part
      # @param yield_score_as [String, nil] exposes the fused score under
      #   this column name instead of the default `__score`
      # @raise [ArgumentError] if constant is negative
      def self.rrf(constant: nil, window: nil, yield_score_as: nil)
        Rrf.new(constant: constant, window: window, yield_score_as: yield_score_as)
      end

      # Fuses the two arms' results linearly:
      # `alpha * search_score + beta * vsim_score`. Writing neither alpha nor
      # beta defaults both to 0.3/0.7 server-side; writing exactly one
      # without the other is rejected by the server as more likely a typo.
      #
      # @param alpha [Float, nil] the SEARCH arm's weight
      # @param beta [Float, nil] the VSIM arm's weight
      # @param window [Integer, nil]
      # @param yield_score_as [String, nil]
      # @raise [ArgumentError] if exactly one of alpha/beta is set
      def self.linear(alpha: nil, beta: nil, window: nil, yield_score_as: nil)
        Linear.new(alpha: alpha, beta: beta, window: window, yield_score_as: yield_score_as)
      end

      # Fuses the two arms' results using a caller-supplied expression,
      # compiled against a context where each arm's score is reachable via
      # its own YIELD_SCORE_AS alias (if any) or the positional defaults
      # `@__search_score` / `@__vector_score`. A valkey-search extension not
      # present in RediSearch's FT.HYBRID.
      #
      # @param expr [String] the fusion expression
      # @param window [Integer, nil] defaults, if unset, to the widest window
      #   the server allows (not the usual RRF/LINEAR default)
      # @param yield_score_as [String, nil]
      def self.function(expr, window: nil, yield_score_as: nil)
        Function.new(expr, window: window, yield_score_as: yield_score_as)
      end

      # @api private
      class Rrf < HybridCombine
        def initialize(constant: nil, window: nil, yield_score_as: nil)
          super()
          raise ArgumentError, "constant must not be negative" if !constant.nil? && constant.negative?

          @constant = constant
          @window = window
          @yield_score_as = yield_score_as
        end

        def to_args
          sub_args = []
          sub_args.push(HybridKeywords::CONSTANT, @constant) unless @constant.nil?
          sub_args.push(HybridKeywords::WINDOW, @window) unless @window.nil?
          sub_args.push(HybridKeywords::YIELD_SCORE_AS, @yield_score_as) unless @yield_score_as.nil?
          [HybridKeywords::COMBINE, HybridKeywords::RRF, sub_args.length, *sub_args]
        end
      end

      # @api private
      class Linear < HybridCombine
        def initialize(alpha: nil, beta: nil, window: nil, yield_score_as: nil)
          super()
          raise ArgumentError, "alpha and beta must both be set, or both left unset" if alpha.nil? != beta.nil?

          @alpha = alpha
          @beta = beta
          @window = window
          @yield_score_as = yield_score_as
        end

        def to_args
          sub_args = []
          sub_args.push(HybridKeywords::ALPHA, @alpha) unless @alpha.nil?
          sub_args.push(HybridKeywords::BETA, @beta) unless @beta.nil?
          sub_args.push(HybridKeywords::WINDOW, @window) unless @window.nil?
          sub_args.push(HybridKeywords::YIELD_SCORE_AS, @yield_score_as) unless @yield_score_as.nil?
          [HybridKeywords::COMBINE, HybridKeywords::LINEAR, sub_args.length, *sub_args]
        end
      end

      # @api private
      class Function < HybridCombine
        def initialize(expr, window: nil, yield_score_as: nil)
          super()
          @expr = expr
          @window = window
          @yield_score_as = yield_score_as
        end

        def to_args
          sub_args = [HybridKeywords::EXPR, @expr]
          sub_args.push(HybridKeywords::WINDOW, @window) unless @window.nil?
          sub_args.push(HybridKeywords::YIELD_SCORE_AS, @yield_score_as) unless @yield_score_as.nil?
          [HybridKeywords::COMBINE, HybridKeywords::FUNCTION, sub_args.length, *sub_args]
        end
      end
    end

    # Options for the FT.HYBRID command's aggregate-suffix tail, applied
    # after the mandatory SEARCH, VSIM and optional COMBINE clauses (which
    # are passed directly to {Valkey::Commands::VectorSearchCommands#ft_hybrid}, not through
    # this class).
    #
    # @example
    #   Valkey::Search::HybridOptions.new(
    #     combine: Valkey::Search::HybridCombine.rrf(constant: 60),
    #     load_fields: ["title"],
    #     with_cursor: Valkey::Search::WithCursor.new(count: 10))
    class HybridOptions
      attr_reader :combine, :load_all, :load_fields, :clauses, :with_cursor,
                  :local_only, :timeout, :params, :dialect

      # @param combine [HybridCombine, nil] controls how the SEARCH and VSIM
      #   arms' scores are fused. If omitted, the server's own default applies.
      # @param load_all [Boolean] loads every field declared in the index,
      #   plus both arms' score aliases automatically (`LOAD *`)
      # @param load_fields [Array<String, LoadField>, nil] loads only the
      #   fields passed here. Must NOT include either arm's yield_score_as
      #   alias — the server rejects that outright even though the alias is
      #   otherwise freely reachable from clauses. With no LOAD clause at all,
      #   FT.HYBRID's default reply is the document key and the fused score.
      # @param clauses [Array<AggregateClause>, nil] FILTER, LIMIT, GROUPBY,
      #   SORTBY and APPLY clauses, reusing {AggregateClause} and its
      #   subclasses verbatim — FT.HYBRID forwards this tail to the same
      #   aggregate pipeline parser FT.AGGREGATE uses. `to_args` always emits
      #   `clauses` after `params`'s own tokens (PARAMS is always present for
      #   FT.HYBRID) — emitting a leading FILTER right after the VSIM arm
      #   would otherwise let the server's VSIM parser claim it as a VSIM
      #   pre-filter instead (confirmed in #7335 review; `ft_hybrid_parser.cc`'s
      #   `vsim_scoped` FILTER handling). FT.HYBRID also applies its own
      #   default LIMIT of 10 rows when no {Limit} clause is given here.
      # @param with_cursor [WithCursor, nil] requests a paged reply
      # @param local_only [Boolean] restricts the query to the local shard.
      #   A valkey-search extension not present in RediSearch's FT.HYBRID.
      #   LOCALONLY is accepted anywhere in the tail before PARAMS but
      #   rejected ("Unexpected argument `LOCALONLY`") once PARAMS has been
      #   parsed. `to_args` always emits it before `params` and `clauses`.
      # @param timeout [Integer, nil] overrides the module's timeout, in ms
      # @param params [Hash, nil] param key/value pairs. Substituted only
      #   into the VSIM arm's `$name` vector reference and into clause
      #   expression text (FILTER, APPLY). The SEARCH arm's query text is
      #   not substituted — like FT.SEARCH, a `$name` reference there is
      #   either taken as literal text or rejected, never replaced.
      # @param dialect [Integer, nil] FT.HYBRID is fixed at dialect 2
      #   server-side; passing any other value is rejected by the server
      def initialize(combine: nil, load_all: false, load_fields: nil, clauses: nil,
                     with_cursor: nil, local_only: false, timeout: nil, params: nil, dialect: nil)
        @combine = combine
        @load_all = load_all
        @load_fields = load_fields
        @clauses = clauses
        @with_cursor = with_cursor
        @local_only = local_only
        @timeout = timeout
        @params = params
        @dialect = dialect
      end

      # Merge {#params} with an internally generated VSIM PARAMS entry,
      # raising if the generated name collides with a caller-supplied one.
      #
      # @api private
      def merge_params(generated_vsim_param)
        merged = @params ? @params.dup : {}
        generated_vsim_param&.each do |name, value|
          if merged.key?(name)
            raise ArgumentError,
                  "Generated VSIM parameter name #{name.inspect} collides with an entry already " \
                  "present in params; rename the caller-supplied params entry"
          end
          merged[name] = value
        end
        merged
      end

      # @param generated_vsim_param [Hash, nil] an internally generated
      #   PARAMS entry for a {HybridVsimArm} given raw vector bytes, merged
      #   with {#params} here. Supplied by {Valkey::Commands::VectorSearchCommands#ft_hybrid};
      #   not intended to be set directly by callers.
      # @return [Array] the optional arguments for FT.HYBRID's aggregate-suffix tail
      def to_args(generated_vsim_param: nil)
        args = []
        # Must come before PARAMS — see the docstring above. Always emitted
        # this early regardless of field-construction order.
        args << HybridKeywords::LOCALONLY if @local_only
        if @load_all
          args.push("LOAD", "*")
        else
          args.concat(Search.load_fields_to_args(@load_fields))
        end
        args.push(HybridKeywords::TIMEOUT, @timeout) unless @timeout.nil?
        args.concat(Search.params_to_args(merge_params(generated_vsim_param), params_keyword: HybridKeywords::PARAMS))
        # Must come after PARAMS — see the docstring above.
        @clauses&.each { |clause| args.concat(clause.to_args) }
        args.concat(@with_cursor.to_args) unless @with_cursor.nil?
        args.push(HybridKeywords::DIALECT, @dialect) unless @dialect.nil?
        args
      end
    end
  end
end
