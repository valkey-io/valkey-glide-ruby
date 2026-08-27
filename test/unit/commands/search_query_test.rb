# frozen_string_literal: true

# Pure unit tests for the Phase 2 Valkey::Search query API — SearchOptions
# serialization (TDD 6.2), SearchResult parsing (TDD 6.4), and ft_search dispatch
# (returns SearchResult on the builder path, raw Array on the raw path).
#
# No server: options are asserted via #to_args, SearchResult via from_raw against
# synthetic replies, and ft_search against a fake client that captures the
# arguments handed to send_command and returns a canned raw reply.
$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require "minitest/autorun"
require "valkey/request_type"
require "valkey/search"
require "valkey/commands/vector_search_commands"

class TestSearchQuery < Minitest::Test
  # Captures send_command and returns a canned reply so ft_search can build a
  # SearchResult without a live server.
  class FakeClient
    include Valkey::Commands::VectorSearchCommands

    attr_reader :captured_type, :captured_args
    attr_accessor :canned_reply

    def initialize(canned_reply = [0])
      @canned_reply = canned_reply
    end

    def send_command(command_type, command_args = [])
      @captured_type = command_type
      @captured_args = command_args
      @canned_reply
    end
  end

  # ---- SearchOptions serialization (TDD 6.2) ----

  def test_empty_options
    assert_equal [], Valkey::Search::SearchOptions.new.to_args
  end

  def test_limit_hash_and_array
    assert_equal ["LIMIT", 0, 10], Valkey::Search::SearchOptions.new(limit: { offset: 0, count: 10 }).to_args
    assert_equal ["LIMIT", 5, 20], Valkey::Search::SearchOptions.new(limit: [5, 20]).to_args
  end

  def test_return_fields_plain_and_aliased
    opts = Valkey::Search::SearchOptions.new(
      return_fields: ["title", { name: "loc", as: "location" }]
    )
    # RETURN count counts every following token: title(1) + loc AS location(3) = 4
    assert_equal ["RETURN", 4, "title", "loc", "AS", "location"], opts.to_args
  end

  def test_sort_by_default_asc_and_desc
    assert_equal %w[SORTBY price ASC], Valkey::Search::SearchOptions.new(sort_by: "price").to_args
    assert_equal %w[SORTBY price DESC],
                 Valkey::Search::SearchOptions.new(sort_by: "price", sort_order: :desc).to_args
  end

  def test_params_nargs_is_twice_pairs
    opts = Valkey::Search::SearchOptions.new(params: { vec: "BLOB", k: "5" })
    assert_equal ["PARAMS", 4, "vec", "BLOB", "k", "5"], opts.to_args
  end

  def test_flags_and_scalars
    opts = Valkey::Search::SearchOptions.new(
      no_content: true, verbatim: true, in_order: true, slop: 2,
      sort_by: "price", with_sort_keys: true, dialect: 2, timeout: 500
    )
    assert_equal ["NOCONTENT", "VERBATIM", "INORDER", "SLOP", 2,
                  "SORTBY", "price", "ASC", "WITHSORTKEYS", "DIALECT", 2, "TIMEOUT", 500],
                 opts.to_args
  end

  def test_shard_scope_and_consistency
    opts = Valkey::Search::SearchOptions.new(shard_scope: :all_shards, consistency: :consistent)
    assert_equal %w[ALLSHARDS CONSISTENT], opts.to_args
  end

  def test_full_option_order
    opts = Valkey::Search::SearchOptions.new(
      no_content: false, verbatim: true, in_order: true, slop: 1,
      limit: { offset: 0, count: 10 }, return_fields: ["title"],
      sort_by: "price", sort_order: :desc, with_sort_keys: true,
      params: { vec: "B" }, dialect: 2, timeout: 100,
      shard_scope: :some_shards, consistency: :inconsistent
    )
    assert_equal ["VERBATIM", "INORDER", "SLOP", 1, "LIMIT", 0, 10,
                  "RETURN", 1, "title", "SORTBY", "price", "DESC", "WITHSORTKEYS",
                  "PARAMS", 2, "vec", "B", "DIALECT", 2, "TIMEOUT", 100,
                  "SOMESHARDS", "INCONSISTENT"], opts.to_args
  end

  def test_rejects_unknown_shard_scope_and_consistency
    assert_raises(ArgumentError) { Valkey::Search::SearchOptions.new(shard_scope: :bogus) }
    assert_raises(ArgumentError) { Valkey::Search::SearchOptions.new(consistency: :maybe) }
  end

  def test_rejects_bad_limit_and_return_field
    assert_raises(ArgumentError) { Valkey::Search::SearchOptions.new(limit: 10) }
    assert_raises(ArgumentError) { Valkey::Search::SearchOptions.new(return_fields: [123]) }
    assert_raises(ArgumentError) { Valkey::Search::SearchOptions.new(return_fields: [{ as: "x" }]) }
  end

  # ---- SearchResult parsing (TDD 6.4) ----

  def test_from_raw_flat_form_with_content
    raw = [2, "doc:1", %w[title Hello], "doc:2", %w[title World]]
    result = Valkey::Search::SearchResult.from_raw(raw)
    assert_equal 2, result.total_results
    assert_equal 2, result.documents.length
    assert_equal "doc:1", result.documents[0].key
    assert_equal({ "title" => "Hello" }, result.documents[0].fields)
    assert_equal "World", result.documents[1].fields["title"]
  end

  def test_from_raw_map_form
    raw = [2, { "doc:1" => { "title" => "Hello" }, "doc:2" => { "title" => "World" } }]
    result = Valkey::Search::SearchResult.from_raw(raw)
    assert_equal 2, result.total_results
    keys = result.documents.map(&:key).sort
    assert_equal ["doc:1", "doc:2"], keys
    doc1 = result.documents.find { |d| d.key == "doc:1" }
    assert_equal({ "title" => "Hello" }, doc1.fields)
  end

  def test_from_raw_no_content
    raw = [3, "doc:1", "doc:2", "doc:3"]
    result = Valkey::Search::SearchResult.from_raw(raw, no_content: true)
    assert_equal 3, result.total_results
    assert_equal ["doc:1", "doc:2", "doc:3"], result.documents.map(&:key)
    assert_empty result.documents[0].fields
  end

  def test_from_raw_with_sort_keys
    raw = [1, "doc:1", "42", %w[price 42]]
    result = Valkey::Search::SearchResult.from_raw(raw, with_sort_keys: true)
    assert_equal 1, result.total_results
    assert_equal "doc:1", result.documents[0].key
    assert_equal "42", result.documents[0].sort_key
    assert_equal({ "price" => "42" }, result.documents[0].fields)
  end

  def test_from_raw_empty_and_zero
    assert_equal 0, Valkey::Search::SearchResult.from_raw([]).total_results
    result = Valkey::Search::SearchResult.from_raw([0])
    assert_equal 0, result.total_results
    assert_empty result.documents
  end

  # ---- ft_search dispatch ----

  def test_ft_search_builder_with_options_object_returns_search_result
    client = FakeClient.new([1, "doc:1", %w[title Hello]])
    opts = Valkey::Search::SearchOptions.new(limit: { offset: 0, count: 10 }, sort_by: "price")
    result = client.ft_search("idx", "@title:hello", opts)

    assert_equal Valkey::RequestType::FT_SEARCH, client.captured_type
    assert_equal ["idx", "@title:hello", "LIMIT", 0, 10, "SORTBY", "price", "ASC"], client.captured_args
    assert_instance_of Valkey::Search::SearchResult, result
    assert_equal 1, result.total_results
    assert_equal "doc:1", result.documents[0].key
  end

  def test_ft_search_builder_with_kwargs_returns_search_result
    client = FakeClient.new([0])
    result = client.ft_search("idx", "*", limit: [0, 5], no_content: true)
    assert_equal ["idx", "*", "NOCONTENT", "LIMIT", 0, 5], client.captured_args
    assert_instance_of Valkey::Search::SearchResult, result
  end

  def test_ft_search_raw_args_returns_raw_array
    raw = [1, "doc:1", %w[title Hello]]
    client = FakeClient.new(raw)
    result = client.ft_search("idx", "@title:hello", "LIMIT", "0", "10")
    assert_equal ["idx", "@title:hello", "LIMIT", "0", "10"], client.captured_args
    assert_same raw, result, "raw-args path must return the unwrapped reply"
  end

  def test_ft_search_no_args_returns_raw_array
    raw = [0]
    client = FakeClient.new(raw)
    result = client.ft_search("idx", "*")
    assert_equal ["idx", "*"], client.captured_args
    assert_same raw, result
  end

  def test_ft_search_rejects_options_and_kwargs_conflict
    client = FakeClient.new
    opts = Valkey::Search::SearchOptions.new(dialect: 2)
    assert_raises(ArgumentError) { client.ft_search("idx", "q", opts, dialect: 2) }
  end

  def test_ft_search_rejects_extra_positional_with_options
    client = FakeClient.new
    opts = Valkey::Search::SearchOptions.new(dialect: 2)
    assert_raises(ArgumentError) { client.ft_search("idx", "q", opts, "EXTRA") }
  end

  def test_ft_search_rejects_raw_tokens_mixed_with_kwargs
    client = FakeClient.new
    assert_raises(ArgumentError) { client.ft_search("idx", "q", "LIMIT", "0", "10", dialect: 2) }
  end

  # ---- QA Round 3 mitigations ----

  # F-SPEC-4: DIALECT is pinned to v2 on Valkey-native search.
  def test_dialect_only_v2_allowed
    assert_equal ["DIALECT", 2], Valkey::Search::SearchOptions.new(dialect: 2).to_args
    assert_equal [], Valkey::Search::SearchOptions.new(dialect: nil).to_args
    assert_raises(ArgumentError) { Valkey::Search::SearchOptions.new(dialect: 1) }
    assert_raises(ArgumentError) { Valkey::Search::SearchOptions.new(dialect: 3) }
  end

  # F-DOM-4: WITHSORTKEYS without SORTBY corrupts the parser; reject it.
  def test_with_sort_keys_requires_sort_by
    assert_raises(ArgumentError) { Valkey::Search::SearchOptions.new(with_sort_keys: true) }
    # valid when paired with sort_by
    opts = Valkey::Search::SearchOptions.new(with_sort_keys: true, sort_by: "price")
    assert_includes opts.to_args, "WITHSORTKEYS"
  end

  # F-DOM-6: sort_order typos must not silently coerce to ASC.
  def test_sort_order_validated
    assert_raises(ArgumentError) { Valkey::Search::SearchOptions.new(sort_by: "p", sort_order: :ascending) }
    assert_equal %w[SORTBY p DESC],
                 Valkey::Search::SearchOptions.new(sort_by: "p", sort_order: :desc).to_args
  end

  # F-DOM-5: limit Array must be [offset, count].
  def test_limit_array_arity
    assert_raises(ArgumentError) { Valkey::Search::SearchOptions.new(limit: [5]) }
    assert_raises(ArgumentError) { Valkey::Search::SearchOptions.new(limit: [1, 2, 3]) }
  end

  # F1: map (cluster) reply honors WITHSORTKEYS ([sort_key, field_map]) and NOCONTENT.
  def test_from_raw_map_with_sort_keys
    raw = [1, { "doc:1" => ["42", { "price" => "42" }] }]
    result = Valkey::Search::SearchResult.from_raw(raw, with_sort_keys: true)
    doc = result.documents.first
    assert_equal "doc:1", doc.key
    assert_equal "42", doc.sort_key
    assert_equal({ "price" => "42" }, doc.fields)
  end

  def test_from_raw_map_no_content
    raw = [1, { "doc:1" => nil }]
    result = Valkey::Search::SearchResult.from_raw(raw, no_content: true)
    assert_equal "doc:1", result.documents.first.key
    assert_empty result.documents.first.fields
  end

  # F2: odd-length field array must not raise.
  def test_from_raw_flat_odd_length_fields
    raw = [1, "doc:1", %w[title Hello dangling]]
    result = Valkey::Search::SearchResult.from_raw(raw)
    assert_equal "Hello", result.documents.first.fields["title"]
    assert_nil result.documents.first.fields["dangling"]
  end

  # F-AP-4: a non-integer count surfaces loudly, not as "0 results".
  def test_from_raw_rejects_non_integer_count
    assert_raises(TypeError) { Valkey::Search::SearchResult.from_raw(["not-a-number", "doc:1", []]) }
  end

  # STOPWORDS []: empty array must not emit "STOPWORDS 0".
  def test_create_options_empty_stopwords_emits_nothing
    assert_equal [], Valkey::Search::CreateOptions.new(stopwords: []).to_args
  end

  # F-DRY-1: the shared lookup_token helper backs the enum validations.
  def test_lookup_token_helper
    assert_equal "HASH", Valkey::Search.lookup_token({ hash: "HASH" }, :hash, "data type")
    assert_equal "HASH", Valkey::Search.lookup_token({ hash: "HASH" }, "HASH", "data type")
    assert_raises(ArgumentError) { Valkey::Search.lookup_token({ hash: "HASH" }, :nope, "data type") }
  end

  # ---- R4 regression coverage ----

  # F-PARSE-2: an integer-valued String count is accepted (happy path)...
  def test_coerce_count_accepts_integer_string
    result = Valkey::Search::SearchResult.from_raw(["2", "doc:1", [], "doc:2", []])
    assert_equal 2, result.total_results
  end

  # ...but a Float count is rejected rather than silently truncated (2.5 -> 2).
  def test_coerce_count_rejects_float
    assert_raises(TypeError) { Valkey::Search::SearchResult.from_raw([2.5, "doc:1", []]) }
  end

  # F-PARSE-1: a truncated flat reply raises instead of yielding a phantom doc.
  def test_from_raw_flat_truncated_missing_payload_raises
    assert_raises(TypeError) { Valkey::Search::SearchResult.from_raw([2, "doc:1", %w[f v], "doc:2"]) }
  end

  def test_from_raw_flat_truncated_missing_sort_key_raises
    assert_raises(TypeError) do
      Valkey::Search::SearchResult.from_raw([1, "doc:1"], with_sort_keys: true)
    end
  end

  # F-PARSE-3: map form under WITHSORTKEYS + NOCONTENT — value is the bare sort
  # key (no field map). The sort key must be preserved, not dropped.
  def test_from_raw_map_with_sort_keys_no_content
    raw = [1, { "doc:1" => "42" }]
    result = Valkey::Search::SearchResult.from_raw(raw, with_sort_keys: true, no_content: true)
    doc = result.documents[0]
    assert_equal "doc:1", doc.key
    assert_equal "42", doc.sort_key
    assert_empty doc.fields
  end

  # F-DOM-1: a bare Symbol return field is accepted and stringified.
  def test_return_fields_accepts_symbol
    opts = Valkey::Search::SearchOptions.new(return_fields: %i[title price])
    assert_equal ["RETURN", 2, "title", "price"], opts.to_args
  end

  # F-DOM-1: the { name:, as: } Hash accepts String keys too.
  def test_return_fields_hash_string_keys
    opts = Valkey::Search::SearchOptions.new(return_fields: [{ "name" => "loc", "as" => "location" }])
    assert_equal ["RETURN", 3, "loc", "AS", "location"], opts.to_args
  end

  # SOMESHARDS emission (previously only :all_shards was exercised).
  def test_some_shards_emission
    opts = Valkey::Search::SearchOptions.new(shard_scope: :some_shards, consistency: :inconsistent)
    assert_equal %w[SOMESHARDS INCONSISTENT], opts.to_args
  end
end
