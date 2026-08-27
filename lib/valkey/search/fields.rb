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
      # @param sortable [Boolean] emit SORTABLE
      # @param no_stem [Boolean] emit NOSTEM
      # @param weight [Numeric, nil] emit `WEIGHT <weight>`
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
      # @param separator [String, nil] emit `SEPARATOR <sep>`
      # @param case_sensitive [Boolean] emit CASESENSITIVE
      # @param sortable [Boolean] emit SORTABLE
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
      # @param sortable [Boolean] emit SORTABLE
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
      # Distance metrics mapped to wire tokens (Java DistanceMetric).
      DISTANCE_METRICS = { l2: "L2", ip: "IP", cosine: "COSINE" }.freeze
      # Supported vector element types (only FLOAT32, matching Java).
      VECTOR_TYPES = ["FLOAT32"].freeze

      # @param dim [Integer] vector dimensionality
      # @param metric [Symbol, String] :l2, :ip, or :cosine (case-insensitive)
      # @param initial_cap [Integer, nil] emit `INITIAL_CAP <n>`
      def self.flat(name, dim:, metric:, type: "FLOAT32", initial_cap: nil, as: nil)
        new(name, algorithm: "FLAT", dim: dim, metric: metric, type: type,
                  initial_cap: initial_cap, as: as)
      end

      # @param m [Integer, nil] emit `M <n>`
      # @param ef_construction [Integer, nil] emit `EF_CONSTRUCTION <n>`
      # @param ef_runtime [Integer, nil] emit `EF_RUNTIME <n>`
      # (plus the {.flat} params)
      def self.hnsw(name, dim:, metric:, type: "FLOAT32", initial_cap: nil,
                    m: nil, ef_construction: nil, ef_runtime: nil, as: nil)
        new(name, algorithm: "HNSW", dim: dim, metric: metric, type: type,
                  initial_cap: initial_cap, m: m, ef_construction: ef_construction,
                  ef_runtime: ef_runtime, as: as)
      end

      # @api private — prefer {.flat} / {.hnsw}.
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
        Search.lookup_token(DISTANCE_METRICS, metric, "distance metric")
      end

      def normalize_type(type)
        token = type.to_s.upcase
        return token if VECTOR_TYPES.include?(token)

        raise ArgumentError, "unknown vector type #{type.inspect}; expected one of #{VECTOR_TYPES.inspect}"
      end
    end
  end
end
