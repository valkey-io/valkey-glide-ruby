# frozen_string_literal: true

require "test_helper"

class TestFtCreateOptions < Minitest::Test
  def test_empty_options
    opts = Valkey::Search::FtCreateOptions.new
    assert_equal [], opts.to_args
  end

  def test_data_type_hash
    opts = Valkey::Search::FtCreateOptions.new(data_type: :hash)
    assert_equal ["ON", "HASH"], opts.to_args
  end

  def test_data_type_json
    opts = Valkey::Search::FtCreateOptions.new(data_type: :json)
    assert_equal ["ON", "JSON"], opts.to_args
  end

  def test_data_type_string_input
    opts = Valkey::Search::FtCreateOptions.new(data_type: "hash")
    assert_equal ["ON", "HASH"], opts.to_args
  end

  def test_single_prefix
    opts = Valkey::Search::FtCreateOptions.new(prefixes: ["doc:"])
    assert_equal ["PREFIX", "1", "doc:"], opts.to_args
  end

  def test_multiple_prefixes
    opts = Valkey::Search::FtCreateOptions.new(prefixes: ["item:", "product:"])
    assert_equal ["PREFIX", "2", "item:", "product:"], opts.to_args
  end

  def test_filter
    opts = Valkey::Search::FtCreateOptions.new(filter: "@status!='archived'")
    assert_equal ["FILTER", "@status!='archived'"], opts.to_args
  end

  def test_default_language
    opts = Valkey::Search::FtCreateOptions.new(default_language: "spanish")
    assert_equal ["LANGUAGE", "spanish"], opts.to_args
  end

  def test_language_field
    opts = Valkey::Search::FtCreateOptions.new(language_field: "lang")
    assert_equal ["LANGUAGE_FIELD", "lang"], opts.to_args
  end

  def test_default_score
    opts = Valkey::Search::FtCreateOptions.new(default_score: 0.5)
    assert_equal ["SCORE", "0.5"], opts.to_args
  end

  def test_score_field
    opts = Valkey::Search::FtCreateOptions.new(score_field: "priority")
    assert_equal ["SCORE_FIELD", "priority"], opts.to_args
  end

  def test_max_text_fields
    opts = Valkey::Search::FtCreateOptions.new(max_text_fields: true)
    assert_equal ["MAXTEXTFIELDS"], opts.to_args
  end

  def test_no_offsets
    opts = Valkey::Search::FtCreateOptions.new(no_offsets: true)
    assert_equal ["NOOFFSETS"], opts.to_args
  end

  def test_temporary
    opts = Valkey::Search::FtCreateOptions.new(temporary: 3600)
    assert_equal ["TEMPORARY", "3600"], opts.to_args
  end

  def test_no_highlight
    opts = Valkey::Search::FtCreateOptions.new(no_highlight: true)
    assert_equal ["NOHL"], opts.to_args
  end

  def test_no_fields
    opts = Valkey::Search::FtCreateOptions.new(no_fields: true)
    assert_equal ["NOFIELDS"], opts.to_args
  end

  def test_no_freqs
    opts = Valkey::Search::FtCreateOptions.new(no_freqs: true)
    assert_equal ["NOFREQS"], opts.to_args
  end

  def test_stopwords
    opts = Valkey::Search::FtCreateOptions.new(stopwords: ["the", "a", "is"])
    assert_equal ["STOPWORDS", "3", "the", "a", "is"], opts.to_args
  end

  def test_stopwords_empty_disables
    opts = Valkey::Search::FtCreateOptions.new(stopwords: [])
    assert_equal ["STOPWORDS", "0"], opts.to_args
  end

  def test_skip_initial_scan
    opts = Valkey::Search::FtCreateOptions.new(skip_initial_scan: true)
    assert_equal ["SKIPINITIALSCAN"], opts.to_args
  end

  def test_combined_typical
    opts = Valkey::Search::FtCreateOptions.new(
      data_type: :hash,
      prefixes: ["product:"],
      default_language: "english"
    )
    expected = ["ON", "HASH", "PREFIX", "1", "product:", "LANGUAGE", "english"]
    assert_equal expected, opts.to_args
  end

  def test_combined_full
    opts = Valkey::Search::FtCreateOptions.new(
      data_type: :json,
      prefixes: ["item:", "doc:"],
      filter: "@active==true",
      default_language: "french",
      language_field: "lang",
      default_score: 0.8,
      score_field: "priority",
      max_text_fields: true,
      no_offsets: true,
      temporary: 7200,
      no_highlight: true,
      no_fields: true,
      no_freqs: true,
      stopwords: ["le", "la"],
      skip_initial_scan: true
    )
    expected = [
      "ON", "JSON",
      "PREFIX", "2", "item:", "doc:",
      "FILTER", "@active==true",
      "LANGUAGE", "french",
      "LANGUAGE_FIELD", "lang",
      "SCORE", "0.8",
      "SCORE_FIELD", "priority",
      "MAXTEXTFIELDS",
      "NOOFFSETS",
      "TEMPORARY", "7200",
      "NOHL",
      "NOFIELDS",
      "NOFREQS",
      "STOPWORDS", "2", "le", "la",
      "SKIPINITIALSCAN"
    ]
    assert_equal expected, opts.to_args
  end

  def test_ordering_matches_ft_create_spec
    # Verify the arg order follows the FT.CREATE specification:
    # ON type, PREFIX, FILTER, LANGUAGE, LANGUAGE_FIELD, SCORE, SCORE_FIELD,
    # MAXTEXTFIELDS, NOOFFSETS, TEMPORARY, NOHL, NOFIELDS, NOFREQS, STOPWORDS, SKIPINITIALSCAN
    opts = Valkey::Search::FtCreateOptions.new(
      skip_initial_scan: true,
      data_type: :hash,
      no_freqs: true,
      prefixes: ["x:"]
    )
    args = opts.to_args
    on_idx = args.index("ON")
    prefix_idx = args.index("PREFIX")
    nofreqs_idx = args.index("NOFREQS")
    skip_idx = args.index("SKIPINITIALSCAN")

    assert on_idx < prefix_idx, "ON must come before PREFIX"
    assert prefix_idx < nofreqs_idx, "PREFIX must come before NOFREQS"
    assert nofreqs_idx < skip_idx, "NOFREQS must come before SKIPINITIALSCAN"
  end
end
