# frozen_string_literal: true

class Valkey
  # Structured builder API for Valkey Search (FT.*) commands. Field and option
  # builders serialize to the flat FT.* token arrays via #to_args, modeled on the
  # Java GLIDE client, adapted to Ruby idiom.
  #
  # @see https://redis.io/commands/ft.create/
  module Search
    # Base class for a SCHEMA field. Subclasses implement #type_args; #to_args
    # prepends the identifier and optional `AS <alias>` (Java FieldInfo ordering).
    #
    # @abstract
    class Field
      # @return [String] the field identifier
      attr_reader :name
      # @return [String, nil] optional attribute alias (AS clause)
      attr_reader :alias_name

      def initialize(name, as: nil)
        @name = name
        @alias_name = as
      end

      # @return [Array] flat FT.CREATE SCHEMA token array for this field
      def to_args
        args = [name]
        args.push("AS", alias_name) if alias_name
        args.concat(type_args)
        args
      end

      # @return [Array] the field-type-specific tokens
      def type_args
        raise NotImplementedError, "#{self.class} must implement #type_args"
      end
    end

    # A full-text (TEXT) field.
    #
    # @example
    #   Valkey::Search::TextField.new("title", sortable: true, weight: 2.0)
    class TextField < Field
      # @param [String] name - the field identifier
      # @param [String, nil] as - optional attribute alias
      # @param [Boolean] sortable - emit SORTABLE
      # @param [Boolean] no_stem - emit NOSTEM
      # @param [Numeric, nil] weight - emit `WEIGHT <weight>`
      def initialize(name, as: nil, sortable: false, no_stem: false, weight: nil)
        super(name, as: as)
        @sortable = sortable
        @no_stem = no_stem
        @weight = weight
      end

      def type_args
        args = ["TEXT"]
        args << "NOSTEM" if @no_stem
        args.push("WEIGHT", @weight) unless @weight.nil?
        args << "SORTABLE" if @sortable
        args
      end
    end

    # A TAG field (exact-match, separator-delimited tokens).
    #
    # @example
    #   Valkey::Search::TagField.new("category", separator: ",", case_sensitive: true)
    class TagField < Field
      # @param [String] name - the field identifier
      # @param [String, nil] as - optional attribute alias
      # @param [String, nil] separator - emit `SEPARATOR <sep>`
      # @param [Boolean] case_sensitive - emit CASESENSITIVE
      # @param [Boolean] sortable - emit SORTABLE
      def initialize(name, as: nil, separator: nil, case_sensitive: false, sortable: false)
        super(name, as: as)
        @separator = separator
        @case_sensitive = case_sensitive
        @sortable = sortable
      end

      def type_args
        args = ["TAG"]
        args.push("SEPARATOR", @separator) unless @separator.nil?
        args << "CASESENSITIVE" if @case_sensitive
        args << "SORTABLE" if @sortable
        args
      end
    end

    # A NUMERIC field.
    #
    # @example
    #   Valkey::Search::NumericField.new("price", sortable: true)
    class NumericField < Field
      # @param [String] name - the field identifier
      # @param [String, nil] as - optional attribute alias
      # @param [Boolean] sortable - emit SORTABLE
      def initialize(name, as: nil, sortable: false)
        super(name, as: as)
        @sortable = sortable
      end

      def type_args
        args = ["NUMERIC"]
        args << "SORTABLE" if @sortable
        args
      end
    end

    # A VECTOR field for similarity search. Construct via {.flat} or {.hnsw}
    # (mirrors Java VectorFieldFlat / VectorFieldHnsw). The count emitted after
    # the algorithm is the number of attribute tokens that follow.
    #
    # @example
    #   Valkey::Search::VectorField.hnsw("embedding", dim: 1536, metric: :cosine, m: 40)
    class VectorField < Field
      # @param [String] name - the field identifier
      # @param [Integer] dim - vector dimensionality
      # @param [Symbol, String] metric - :l2, :ip, or :cosine (case-insensitive)
      # @param [String] type - vector element type
      # @param [Integer, nil] initial_cap - emit `INITIAL_CAP <n>`
      # @param [String, nil] as - optional attribute alias
      #
      # @return [VectorField] the configured FLAT vector field
      def self.flat(name, dim:, metric:, type: "FLOAT32", initial_cap: nil, as: nil)
        new(name, algorithm: "FLAT", dim: dim, metric: metric, type: type,
                  initial_cap: initial_cap, as: as)
      end

      # @param [String] name - the field identifier
      # @param [Integer] dim - vector dimensionality
      # @param [Symbol, String] metric - :l2, :ip, or :cosine (case-insensitive)
      # @param [String] type - vector element type
      # @param [Integer, nil] initial_cap - emit `INITIAL_CAP <n>`
      # @param [Integer, nil] m - emit `M <n>`
      # @param [Integer, nil] ef_construction - emit `EF_CONSTRUCTION <n>`
      # @param [Integer, nil] ef_runtime - emit `EF_RUNTIME <n>`
      # @param [String, nil] as - optional attribute alias
      #
      # @return [VectorField] the configured HNSW vector field
      def self.hnsw(name, dim:, metric:, type: "FLOAT32", initial_cap: nil,
                    m: nil, ef_construction: nil, ef_runtime: nil, as: nil)
        new(name, algorithm: "HNSW", dim: dim, metric: metric, type: type,
                  initial_cap: initial_cap, m: m, ef_construction: ef_construction,
                  ef_runtime: ef_runtime, as: as)
      end

      # Prefer {.flat} or {.hnsw}.
      #
      # @param [String] name - the field identifier
      # @param [String] algorithm - vector index algorithm
      # @param [Integer] dim - vector dimensionality
      # @param [Symbol, String] metric - distance metric
      # @param [String] type - vector element type
      # @param [Integer, nil] initial_cap - initial vector capacity
      # @param [Integer, nil] m - HNSW maximum outgoing edges
      # @param [Integer, nil] ef_construction - HNSW construction search width
      # @param [Integer, nil] ef_runtime - HNSW runtime search width
      # @param [String, nil] as - optional attribute alias
      #
      # @api private
      def initialize(name, algorithm:, dim:, metric:, type: "FLOAT32",
                     initial_cap: nil, m: nil, ef_construction: nil, ef_runtime: nil, as: nil)
        super(name, as: as)
        @algorithm = algorithm
        @dim = dim
        @metric = normalize_metric(metric)
        @type = normalize_type(type)
        @initial_cap = initial_cap
        @m = m
        @ef_construction = ef_construction
        @ef_runtime = ef_runtime
      end

      def type_args
        attrs = ["TYPE", @type, "DIM", @dim, "DISTANCE_METRIC", @metric]
        attrs.push("INITIAL_CAP", @initial_cap) unless @initial_cap.nil?
        attrs.push("M", @m) unless @m.nil?
        attrs.push("EF_CONSTRUCTION", @ef_construction) unless @ef_construction.nil?
        attrs.push("EF_RUNTIME", @ef_runtime) unless @ef_runtime.nil?
        ["VECTOR", @algorithm, attrs.length, *attrs]
      end

      private

      def normalize_metric(metric)
        Search.lookup_token(Search::DISTANCE_METRICS, metric, "distance metric")
      end

      def normalize_type(type)
        token = type.to_s.upcase
        return token if Search::VECTOR_TYPES.include?(token)

        raise ArgumentError, "unknown vector type #{type.inspect}; expected one of #{Search::VECTOR_TYPES.inspect}"
      end
    end
  end
end
