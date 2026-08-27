# frozen_string_literal: true

class Valkey
  module Search
    # Index-level options for FT.CREATE (everything before SCHEMA). Mirrors the
    # Java FTCreateOptions.
    #
    # @example
    #   Valkey::Search::CreateOptions.new(on: :hash, prefixes: ["doc:"], skip_initial_scan: true)
    #
    # @see https://redis.io/commands/ft.create/
    class CreateOptions
      DATA_TYPES = { hash: "HASH", json: "JSON" }.freeze

      # @param on [Symbol, String, nil] :hash or :json (ON clause)
      # @param prefixes [Array<String>, nil] key prefixes (`PREFIX <count> <p...>`)
      # @param score [Numeric, nil] default document score
      # @param language [String, nil] default stemmer language
      # @param skip_initial_scan [Boolean] emit SKIPINITIALSCAN
      # @param min_stem_size [Integer, nil] emit `MINSTEMSIZE <n>`
      # @param stopwords [Array<String>, nil] custom stopwords (mutually exclusive with no_stopwords)
      # @param no_stopwords [Boolean] emit NOSTOPWORDS
      def initialize(on: nil, prefixes: nil, score: nil, language: nil,
                     skip_initial_scan: false, min_stem_size: nil,
                     stopwords: nil, no_stopwords: false)
        raise ArgumentError, "stopwords and no_stopwords are mutually exclusive" if !stopwords.nil? && no_stopwords

        @on = on.nil? ? nil : normalize_on(on)
        @prefixes = prefixes
        @score = score
        @language = language
        @skip_initial_scan = skip_initial_scan
        @min_stem_size = min_stem_size
        @stopwords = stopwords
        @no_stopwords = no_stopwords
      end

      # @return [Array] FT.CREATE option tokens (before SCHEMA)
      def to_args
        args = []
        args.push("ON", @on) unless @on.nil?
        args.push("PREFIX", @prefixes.length, *@prefixes) if @prefixes && !@prefixes.empty?
        args.push("SCORE", @score) unless @score.nil?
        args.push("LANGUAGE", @language) unless @language.nil?
        args << "SKIPINITIALSCAN" if @skip_initial_scan
        args.push("MINSTEMSIZE", @min_stem_size) unless @min_stem_size.nil?
        args.push("STOPWORDS", @stopwords.length, *@stopwords) if @stopwords && !@stopwords.empty?
        args << "NOSTOPWORDS" if @no_stopwords
        args
      end

      private

      def normalize_on(on)
        Search.lookup_token(DATA_TYPES, on, "data type")
      end
    end
  end
end
