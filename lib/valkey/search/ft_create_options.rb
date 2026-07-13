# frozen_string_literal: true

class Valkey
  module Search
    # Index-level options for FT.CREATE.
    #
    # Encapsulates the options that appear *before* the SCHEMA keyword in an
    # FT.CREATE command: data type (HASH/JSON), key prefixes, filters, default
    # language, score, and other index-wide settings.
    #
    # @example Basic usage
    #   opts = Valkey::Search::FtCreateOptions.new(
    #     data_type: :hash,
    #     prefixes: ["product:"]
    #   )
    #   opts.to_args
    #   # => ["ON", "HASH", "PREFIX", "1", "product:"]
    #
    # @example Full options
    #   opts = Valkey::Search::FtCreateOptions.new(
    #     data_type: :json,
    #     prefixes: ["item:", "doc:"],
    #     filter: "@status!='archived'",
    #     default_language: "english",
    #     language_field: "lang",
    #     default_score: 0.5,
    #     score_field: "priority",
    #     max_text_fields: true,
    #     no_offsets: true,
    #     temporary: 3600,
    #     no_highlight: true,
    #     no_fields: true,
    #     no_freqs: true,
    #     stopwords: ["the", "a", "is"],
    #     skip_initial_scan: true
    #   )
    #
    # @see https://valkey.io/commands/ft.create/
    class FtCreateOptions
      # @return [Symbol, nil] :hash or :json (ON HASH / ON JSON)
      attr_reader :data_type

      # @return [Array<String>] key prefixes to index
      attr_reader :prefixes

      # @return [String, nil] filter expression for conditional indexing
      attr_reader :filter

      # @return [String, nil] default language for stemming
      attr_reader :default_language

      # @return [String, nil] document field that holds the language
      attr_reader :language_field

      # @return [Float, nil] default document score (0.0–1.0)
      attr_reader :default_score

      # @return [String, nil] document field that holds the score
      attr_reader :score_field

      # @return [Boolean] allow unlimited TEXT fields
      attr_reader :max_text_fields

      # @return [Boolean] disable offset storage (saves memory, disables exact phrase search)
      attr_reader :no_offsets

      # @return [Integer, nil] TTL in seconds for a temporary index
      attr_reader :temporary

      # @return [Boolean] disable highlight/snippet support
      attr_reader :no_highlight

      # @return [Boolean] disable field storage (saves memory, disables RETURN)
      attr_reader :no_fields

      # @return [Boolean] disable term frequency tracking
      attr_reader :no_freqs

      # @return [Array<String>, nil] custom stopwords (empty array = no stopwords)
      attr_reader :stopwords

      # @return [Boolean] skip the initial full-key-space scan on creation
      attr_reader :skip_initial_scan

      # @param data_type [Symbol, String, nil] :hash or :json
      # @param prefixes [Array<String>] key prefixes to index
      # @param filter [String, nil] conditional indexing filter
      # @param default_language [String, nil] stemming language
      # @param language_field [String, nil] per-document language field name
      # @param default_score [Float, nil] default document score
      # @param score_field [String, nil] per-document score field name
      # @param max_text_fields [Boolean] allow unlimited TEXT fields
      # @param no_offsets [Boolean] disable offset storage
      # @param temporary [Integer, nil] index TTL in seconds
      # @param no_highlight [Boolean] disable highlighting
      # @param no_fields [Boolean] disable field storage
      # @param no_freqs [Boolean] disable frequency tracking
      # @param stopwords [Array<String>, nil] custom stopwords list
      # @param skip_initial_scan [Boolean] skip initial key scan
      def initialize(data_type: nil, prefixes: [], filter: nil,
                     default_language: nil, language_field: nil,
                     default_score: nil, score_field: nil,
                     max_text_fields: false, no_offsets: false,
                     temporary: nil, no_highlight: false,
                     no_fields: false, no_freqs: false,
                     stopwords: nil, skip_initial_scan: false)
        @data_type = data_type&.to_s&.upcase&.to_sym
        @prefixes = prefixes.map(&:to_s)
        @filter = filter&.to_s
        @default_language = default_language&.to_s
        @language_field = language_field&.to_s
        @default_score = default_score
        @score_field = score_field&.to_s
        @max_text_fields = max_text_fields
        @no_offsets = no_offsets
        @temporary = temporary
        @no_highlight = no_highlight
        @no_fields = no_fields
        @no_freqs = no_freqs
        @stopwords = stopwords&.map(&:to_s)
        @skip_initial_scan = skip_initial_scan
      end

      # Serialize options into the argument array that appears between the index
      # name and the SCHEMA keyword in FT.CREATE.
      #
      # @return [Array<String>]
      def to_args
        args = []
        args.push("ON", @data_type.to_s) if @data_type
        if @prefixes.any?
          args.push("PREFIX", @prefixes.size.to_s)
          args.concat(@prefixes)
        end
        args.push("FILTER", @filter) if @filter
        args.push("LANGUAGE", @default_language) if @default_language
        args.push("LANGUAGE_FIELD", @language_field) if @language_field
        args.push("SCORE", @default_score.to_s) if @default_score
        args.push("SCORE_FIELD", @score_field) if @score_field
        args << "MAXTEXTFIELDS" if @max_text_fields
        args << "NOOFFSETS" if @no_offsets
        args.push("TEMPORARY", @temporary.to_s) if @temporary
        args << "NOHL" if @no_highlight
        args << "NOFIELDS" if @no_fields
        args << "NOFREQS" if @no_freqs
        if @stopwords
          args.push("STOPWORDS", @stopwords.size.to_s)
          args.concat(@stopwords)
        end
        args << "SKIPINITIALSCAN" if @skip_initial_scan
        args
      end
    end
  end
end
