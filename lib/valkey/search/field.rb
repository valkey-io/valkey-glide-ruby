# frozen_string_literal: true

class Valkey
  module Search
    # Base class for FT.CREATE field definitions.
    # Subclasses implement {#to_args} to serialize into the argument array
    # expected by the FT.CREATE SCHEMA clause.
    #
    # @abstract Subclass and override {#to_args}
    class Field
      # @return [String] the field name as it appears in the indexed document
      attr_reader :name

      # @return [String, nil] optional alias used to reference this field in queries
      attr_reader :field_alias

      # @return [Boolean] whether the field is sortable
      attr_reader :sortable

      # @param name [String] field name in the document
      # @param field_alias [String, nil] alias for queries (AS <alias>)
      # @param sortable [Boolean] enable SORTBY on this field
      def initialize(name, field_alias: nil, sortable: false)
        @name = name.to_s
        @field_alias = field_alias&.to_s
        @sortable = sortable
      end

      # Serialize the field definition into an array of strings suitable for
      # appending after the SCHEMA keyword in FT.CREATE.
      #
      # @return [Array<String>]
      # @abstract
      def to_args
        raise NotImplementedError, "#{self.class}#to_args must be implemented"
      end

      private

      # Common trailing args shared by text/numeric/tag fields.
      def base_trailing_args
        args = []
        args.push("AS", @field_alias) if @field_alias
        args
      end

      def sortable_args
        @sortable ? ["SORTABLE"] : []
      end
    end

    # A full-text searchable field.
    #
    # @example
    #   Valkey::Search::TextField.new("title", sortable: true, weight: 2.0)
    #
    # @see https://valkey.io/commands/ft.create/
    class TextField < Field
      # @return [Boolean] disable stemming for this field
      attr_reader :nostem

      # @return [Float, nil] scoring weight (default 1.0)
      attr_reader :weight

      # @return [Boolean] enable suffix trie optimization
      attr_reader :withsuffixtrie

      # @return [Boolean] disable suffix trie optimization
      attr_reader :nosuffixtrie

      # @param name [String] field name
      # @param field_alias [String, nil] query alias
      # @param sortable [Boolean] enable SORTBY
      # @param nostem [Boolean] disable stemming
      # @param weight [Float, nil] scoring weight
      # @param withsuffixtrie [Boolean] enable suffix trie
      # @param nosuffixtrie [Boolean] disable suffix trie
      def initialize(name, field_alias: nil, sortable: false, nostem: false,
                     weight: nil, withsuffixtrie: false, nosuffixtrie: false)
        super(name, field_alias: field_alias, sortable: sortable)
        @nostem = nostem
        @weight = weight
        @withsuffixtrie = withsuffixtrie
        @nosuffixtrie = nosuffixtrie
      end

      # @return [Array<String>]
      def to_args
        args = [@name]
        args.concat(base_trailing_args)
        args << "TEXT"
        args << "NOSTEM" if @nostem
        args.push("WEIGHT", @weight.to_s) if @weight
        args << "WITHSUFFIXTRIE" if @withsuffixtrie
        args << "NOSUFFIXTRIE" if @nosuffixtrie
        args.concat(sortable_args)
        args
      end
    end

    # A numeric field for range queries.
    #
    # @example
    #   Valkey::Search::NumericField.new("price", sortable: true)
    #
    # @see https://valkey.io/commands/ft.create/
    class NumericField < Field
      # @param name [String] field name
      # @param field_alias [String, nil] query alias
      # @param sortable [Boolean] enable SORTBY
      def initialize(name, field_alias: nil, sortable: false)
        super(name, field_alias: field_alias, sortable: sortable)
      end

      # @return [Array<String>]
      def to_args
        args = [@name]
        args.concat(base_trailing_args)
        args << "NUMERIC"
        args.concat(sortable_args)
        args
      end
    end

    # A tag field for exact-match filtering using comma-separated values.
    #
    # @example
    #   Valkey::Search::TagField.new("category", separator: ";", case_sensitive: true)
    #
    # @see https://valkey.io/commands/ft.create/
    class TagField < Field
      # @return [String, nil] separator character (default comma)
      attr_reader :separator

      # @return [Boolean] whether tag matching is case-sensitive
      attr_reader :case_sensitive

      # @param name [String] field name
      # @param field_alias [String, nil] query alias
      # @param sortable [Boolean] enable SORTBY
      # @param separator [String, nil] tag separator character
      # @param case_sensitive [Boolean] enable case-sensitive matching
      def initialize(name, field_alias: nil, sortable: false, separator: nil, case_sensitive: false)
        super(name, field_alias: field_alias, sortable: sortable)
        @separator = separator&.to_s
        @case_sensitive = case_sensitive
      end

      # @return [Array<String>]
      def to_args
        args = [@name]
        args.concat(base_trailing_args)
        args << "TAG"
        args.push("SEPARATOR", @separator) if @separator
        args << "CASESENSITIVE" if @case_sensitive
        args.concat(sortable_args)
        args
      end
    end

    # A vector field using the FLAT (brute-force) indexing algorithm.
    #
    # @example
    #   Valkey::Search::VectorFieldFlat.new("embedding",
    #     dim: 768, distance_metric: :cosine, type: :float32,
    #     initial_cap: 1000)
    #
    # @see https://valkey.io/commands/ft.create/
    class VectorFieldFlat < Field
      # @return [Integer] vector dimensions
      attr_reader :dim

      # @return [Symbol] distance metric (:cosine, :l2, :ip)
      attr_reader :distance_metric

      # @return [Symbol] vector element type (:float32, :float64, :bfloat16, :float16)
      attr_reader :type

      # @return [Integer, nil] initial index capacity
      attr_reader :initial_cap

      # @param name [String] field name
      # @param dim [Integer] number of dimensions
      # @param distance_metric [Symbol, String] :cosine, :l2, or :ip
      # @param type [Symbol, String] :float32, :float64, :bfloat16, or :float16
      # @param field_alias [String, nil] query alias
      # @param initial_cap [Integer, nil] initial vector capacity hint
      def initialize(name, dim:, distance_metric:, type: :float32,
                     field_alias: nil, initial_cap: nil)
        super(name, field_alias: field_alias, sortable: false)
        @dim = dim
        @distance_metric = distance_metric.to_s.upcase.to_sym
        @type = type.to_s.upcase.to_sym
        @initial_cap = initial_cap
      end

      # @return [Array<String>]
      def to_args
        attrs = vector_attributes
        args = [@name]
        args.concat(base_trailing_args)
        args.push("VECTOR", "FLAT", attrs.size.to_s)
        args.concat(attrs)
        args
      end

      private

      def vector_attributes
        attrs = []
        attrs.push("TYPE", @type.to_s)
        attrs.push("DIM", @dim.to_s)
        attrs.push("DISTANCE_METRIC", @distance_metric.to_s)
        attrs.push("INITIAL_CAP", @initial_cap.to_s) if @initial_cap
        attrs
      end
    end

    # A vector field using the HNSW (hierarchical navigable small world) algorithm.
    #
    # @example
    #   Valkey::Search::VectorFieldHnsw.new("embedding",
    #     dim: 768, distance_metric: :cosine, type: :float32,
    #     m: 16, ef_construction: 200, ef_runtime: 10)
    #
    # @see https://valkey.io/commands/ft.create/
    class VectorFieldHnsw < Field
      # @return [Integer] vector dimensions
      attr_reader :dim

      # @return [Symbol] distance metric (:cosine, :l2, :ip)
      attr_reader :distance_metric

      # @return [Symbol] vector element type (:float32, :float64, :bfloat16, :float16)
      attr_reader :type

      # @return [Integer, nil] initial index capacity
      attr_reader :initial_cap

      # @return [Integer, nil] number of edges per node (default 16)
      attr_reader :m

      # @return [Integer, nil] vectors examined during construction (default 200)
      attr_reader :ef_construction

      # @return [Integer, nil] vectors examined during search (default 10)
      attr_reader :ef_runtime

      # @param name [String] field name
      # @param dim [Integer] number of dimensions
      # @param distance_metric [Symbol, String] :cosine, :l2, or :ip
      # @param type [Symbol, String] :float32, :float64, :bfloat16, or :float16
      # @param field_alias [String, nil] query alias
      # @param initial_cap [Integer, nil] initial vector capacity hint
      # @param m [Integer, nil] max edges per node in HNSW graph
      # @param ef_construction [Integer, nil] vectors examined during index build
      # @param ef_runtime [Integer, nil] vectors examined during search
      def initialize(name, dim:, distance_metric:, type: :float32,
                     field_alias: nil, initial_cap: nil,
                     m: nil, ef_construction: nil, ef_runtime: nil)
        super(name, field_alias: field_alias, sortable: false)
        @dim = dim
        @distance_metric = distance_metric.to_s.upcase.to_sym
        @type = type.to_s.upcase.to_sym
        @initial_cap = initial_cap
        @m = m
        @ef_construction = ef_construction
        @ef_runtime = ef_runtime
      end

      # @return [Array<String>]
      def to_args
        attrs = vector_attributes
        args = [@name]
        args.concat(base_trailing_args)
        args.push("VECTOR", "HNSW", attrs.size.to_s)
        args.concat(attrs)
        args
      end

      private

      def vector_attributes
        attrs = []
        attrs.push("TYPE", @type.to_s)
        attrs.push("DIM", @dim.to_s)
        attrs.push("DISTANCE_METRIC", @distance_metric.to_s)
        attrs.push("INITIAL_CAP", @initial_cap.to_s) if @initial_cap
        attrs.push("M", @m.to_s) if @m
        attrs.push("EF_CONSTRUCTION", @ef_construction.to_s) if @ef_construction
        attrs.push("EF_RUNTIME", @ef_runtime.to_s) if @ef_runtime
        attrs
      end
    end
  end
end
