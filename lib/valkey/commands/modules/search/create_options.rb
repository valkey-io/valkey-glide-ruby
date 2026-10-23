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
      # @param [Symbol, String, nil] on - :hash or :json (ON clause)
      # @param [Array<String>, nil] prefixes - key prefixes (`PREFIX <count> <p...>`)
      # @param [Numeric, nil] score - default document score
      # @param [String, nil] language - default stemmer language
      # @param [Boolean] skip_initial_scan - emit SKIPINITIALSCAN
      # @param [Integer, nil] min_stem_size - emit `MINSTEMSIZE <n>`
      # @param [Array<String>, nil] stopwords - custom stopwords (mutually exclusive with no_stopwords)
      # @param [Boolean] no_stopwords - emit NOSTOPWORDS
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
        Search.lookup_token(Search::DATA_TYPES, on, "data type")
      end
    end
  end
end
