# frozen_string_literal: true

# Load only the pieces this unit test needs. Requiring the full "valkey" entry
# point pulls in the native FFI bindings; these tests are pure Ruby (field/option
# serialization + ft_create argument dispatch) and must run without the native
# library present. Under the rake suite, test_helper has already loaded these —
# the requires below are then idempotent no-ops.
$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require "minitest/autorun"
require "valkey/request_type"
require "valkey/search"
require "valkey/route"
require "valkey/commands/vector_search_commands"

# Pure unit tests for the Phase 1 Valkey::Search builder API — field/option
# serialization and the ft_create builder dispatch path.
#
# These tests do not touch a server: field/option objects are asserted via
# #to_args, and ft_create is exercised against a fake client that captures the
# arguments handed to send_command.
class TestSearchBuilder < Minitest::Test
  # Minimal stand-in that mixes in the command module and records the
  # (request_type, args) pair instead of dispatching over FFI.
  class FakeClient
    include Valkey::Commands::VectorSearchCommands

    attr_reader :captured_type, :captured_args, :captured_route

    # Mirrors Valkey#send_command's signature, including the cluster `route:`
    # kwarg, so dispatch-level routing is exercised the way the real client is.
    def send_command(command_type, command_args = [], route: nil)
      @captured_type = command_type
      @captured_args = command_args
      @captured_route = route
      "OK"
    end
  end

  # ---- Field serialization ----

  def test_text_field_basic
    assert_equal %w[title TEXT], Valkey::Search::TextField.new("title").to_args
  end

  def test_text_field_all_options
    field = Valkey::Search::TextField.new("title", sortable: true, no_stem: true, weight: 2.0)
    assert_equal ["title", "TEXT", "NOSTEM", "WEIGHT", 2.0, "SORTABLE"], field.to_args
  end

  def test_text_field_alias
    field = Valkey::Search::TextField.new("title", as: "t")
    assert_equal %w[title AS t TEXT], field.to_args
  end

  def test_tag_field
    field = Valkey::Search::TagField.new("category", separator: ",", case_sensitive: true, sortable: true)
    assert_equal ["category", "TAG", "SEPARATOR", ",", "CASESENSITIVE", "SORTABLE"], field.to_args
  end

  def test_tag_field_defaults
    assert_equal %w[category TAG], Valkey::Search::TagField.new("category").to_args
  end

  def test_numeric_field
    assert_equal %w[price NUMERIC SORTABLE],
                 Valkey::Search::NumericField.new("price", sortable: true).to_args
    assert_equal %w[price NUMERIC], Valkey::Search::NumericField.new("price").to_args
  end

  def test_vector_field_flat
    field = Valkey::Search::VectorField.flat("embedding", dim: 128, metric: :cosine)
    assert_equal ["embedding", "VECTOR", "FLAT", 6,
                  "TYPE", "FLOAT32", "DIM", 128, "DISTANCE_METRIC", "COSINE"], field.to_args
  end

  def test_vector_field_hnsw_with_tuning_and_alias
    field = Valkey::Search::VectorField.hnsw("embedding", dim: 1536, metric: :l2,
                                                          m: 40, ef_construction: 200, as: "vec")
    assert_equal ["embedding", "AS", "vec", "VECTOR", "HNSW", 10,
                  "TYPE", "FLOAT32", "DIM", 1536, "DISTANCE_METRIC", "L2",
                  "M", 40, "EF_CONSTRUCTION", 200], field.to_args
  end

  def test_vector_field_flat_with_initial_cap
    field = Valkey::Search::VectorField.flat("v", dim: 8, metric: :ip, initial_cap: 1000)
    assert_equal ["v", "VECTOR", "FLAT", 8,
                  "TYPE", "FLOAT32", "DIM", 8, "DISTANCE_METRIC", "IP",
                  "INITIAL_CAP", 1000], field.to_args
  end

  def test_vector_field_metric_case_insensitive
    field = Valkey::Search::VectorField.flat("v", dim: 4, metric: "CoSiNe")
    assert_includes field.to_args, "COSINE"
  end

  def test_vector_field_rejects_unknown_metric
    error = assert_raises(ArgumentError) do
      Valkey::Search::VectorField.flat("v", dim: 4, metric: :euclidean)
    end
    assert_match(/unknown distance metric/, error.message)
  end

  def test_base_field_type_args_is_abstract
    assert_raises(NotImplementedError) { Valkey::Search::Field.new("x").to_args }
  end

  # ---- CreateOptions serialization ----

  def test_create_options_empty
    assert_equal [], Valkey::Search::CreateOptions.new.to_args
  end

  def test_create_options_hash_prefix_skipscan
    opts = Valkey::Search::CreateOptions.new(on: :hash, prefixes: ["doc:"], skip_initial_scan: true)
    assert_equal ["ON", "HASH", "PREFIX", 1, "doc:", "SKIPINITIALSCAN"], opts.to_args
  end

  def test_create_options_json_multi_prefix_score_language
    opts = Valkey::Search::CreateOptions.new(on: :json, prefixes: ["a:", "b:"],
                                             score: 0.5, language: "english")
    assert_equal ["ON", "JSON", "PREFIX", 2, "a:", "b:", "SCORE", 0.5, "LANGUAGE", "english"], opts.to_args
  end

  def test_create_options_stopwords
    assert_equal ["STOPWORDS", 2, "the", "a"],
                 Valkey::Search::CreateOptions.new(stopwords: %w[the a]).to_args
    assert_equal ["NOSTOPWORDS"], Valkey::Search::CreateOptions.new(no_stopwords: true).to_args
  end

  def test_create_options_min_stem_size
    assert_equal ["MINSTEMSIZE", 4], Valkey::Search::CreateOptions.new(min_stem_size: 4).to_args
  end

  def test_create_options_rejects_conflicting_stopwords
    assert_raises(ArgumentError) do
      Valkey::Search::CreateOptions.new(stopwords: ["x"], no_stopwords: true)
    end
  end

  def test_create_options_rejects_unknown_data_type
    assert_raises(ArgumentError) { Valkey::Search::CreateOptions.new(on: :bogus) }
  end

  # ---- ft_create dispatch ----

  def test_ft_create_builder_with_kwargs_options
    client = FakeClient.new
    result = client.ft_create("idx",
                              [Valkey::Search::TextField.new("title", sortable: true),
                               Valkey::Search::NumericField.new("price")],
                              on: :hash, prefixes: ["doc:"])
    assert_equal "OK", result
    assert_equal Valkey::RequestType::FT_CREATE, client.captured_type
    assert_equal ["idx", "ON", "HASH", "PREFIX", 1, "doc:",
                  "SCHEMA", "title", "TEXT", "SORTABLE", "price", "NUMERIC"], client.captured_args
  end

  def test_ft_create_builder_with_positional_options_object
    client = FakeClient.new
    opts = Valkey::Search::CreateOptions.new(on: :hash)
    client.ft_create("idx", [Valkey::Search::TextField.new("title")], opts)
    assert_equal %w[idx ON HASH SCHEMA title TEXT], client.captured_args
  end

  def test_ft_create_builder_without_options
    client = FakeClient.new
    client.ft_create("idx", [Valkey::Search::TextField.new("title")])
    assert_equal %w[idx SCHEMA title TEXT], client.captured_args
  end

  def test_ft_create_builder_with_vector_field
    client = FakeClient.new
    client.ft_create("vec", [Valkey::Search::VectorField.hnsw("embedding", dim: 128, metric: :cosine)],
                     on: :hash, prefixes: ["doc:"])
    assert_equal ["vec", "ON", "HASH", "PREFIX", 1, "doc:", "SCHEMA",
                  "embedding", "VECTOR", "HNSW", 6,
                  "TYPE", "FLOAT32", "DIM", 128, "DISTANCE_METRIC", "COSINE"], client.captured_args
  end

  # Raw FT.CREATE token pass-through was removed: the schema must be builders.
  def test_ft_create_rejects_raw_tokens
    client = FakeClient.new
    assert_raises(ArgumentError) { client.ft_create("idx", "SCHEMA", "title") }
  end

  # ---- ft_create dispatch guards ----

  def test_ft_create_raises_on_options_and_kwargs_conflict
    client = FakeClient.new
    opts = Valkey::Search::CreateOptions.new(on: :hash)
    error = assert_raises(ArgumentError) do
      client.ft_create("idx", [Valkey::Search::TextField.new("t")], opts, prefixes: ["doc:"])
    end
    assert_match(/not both/, error.message)
  end

  def test_ft_create_raises_on_non_create_options_positional
    client = FakeClient.new
    error = assert_raises(ArgumentError) do
      client.ft_create("idx", [Valkey::Search::TextField.new("t")], "ON HASH")
    end
    assert_match(/must be a Valkey::Search::CreateOptions/, error.message)
  end

  def test_ft_create_raises_on_empty_schema
    client = FakeClient.new
    error = assert_raises(ArgumentError) { client.ft_create("idx", []) }
    assert_match(/at least one field/, error.message)
  end

  def test_ft_create_raises_on_mixed_array_no_silent_reroute
    client = FakeClient.new
    error = assert_raises(ArgumentError) do
      client.ft_create("idx", [Valkey::Search::TextField.new("t"), "oops"])
    end
    assert_match(/must be a Valkey::Search::Field/, error.message)
  end

  # raw FT.CREATE tokens passed as one Array hit the builder path;
  # the error should hint at the splat requirement.
  # An Array of raw tokens is not a schema; it must be Field objects.
  def test_ft_create_rejects_string_array_schema
    client = FakeClient.new
    error = assert_raises(ArgumentError) do
      client.ft_create("idx", %w[SCHEMA title TEXT])
    end
    assert_match(/must be a Valkey::Search::Field/, error.message)
  end

  def test_ft_create_raises_on_too_many_positionals
    client = FakeClient.new
    opts = Valkey::Search::CreateOptions.new(on: :hash)
    assert_raises(ArgumentError) do
      client.ft_create("idx", [Valkey::Search::TextField.new("t")], opts, "extra")
    end
  end

  # ---- Vector type validation ----

  def test_vector_field_rejects_unknown_type
    error = assert_raises(ArgumentError) do
      Valkey::Search::VectorField.flat("v", dim: 4, metric: :l2, type: "FLOAT64")
    end
    assert_match(/unknown vector type/, error.message)
  end

  def test_vector_field_type_case_insensitive
    field = Valkey::Search::VectorField.flat("v", dim: 4, metric: :l2, type: "float32")
    assert_includes field.to_args, "FLOAT32"
  end

  # ---- Dispatch coverage through ft_create ----

  def test_ft_create_flat_vector_and_tag_through_dispatch
    client = FakeClient.new
    client.ft_create("idx",
                     [Valkey::Search::TagField.new("category", separator: ",", as: "cat"),
                      Valkey::Search::VectorField.flat("embedding", dim: 8, metric: :ip, initial_cap: 100)])
    assert_equal ["idx", "SCHEMA",
                  "category", "AS", "cat", "TAG", "SEPARATOR", ",",
                  "embedding", "VECTOR", "FLAT", 8,
                  "TYPE", "FLOAT32", "DIM", 8, "DISTANCE_METRIC", "IP", "INITIAL_CAP", 100],
                 client.captured_args
  end

  def test_ft_create_text_weight_alias_and_numeric_alias_through_dispatch
    client = FakeClient.new
    client.ft_create("idx",
                     [Valkey::Search::TextField.new("title", weight: 2.0, as: "t"),
                      Valkey::Search::NumericField.new("price", as: "p", sortable: true)])
    assert_equal ["idx", "SCHEMA",
                  "title", "AS", "t", "TEXT", "WEIGHT", 2.0,
                  "price", "AS", "p", "NUMERIC", "SORTABLE"],
                 client.captured_args
  end

  def test_ft_create_score_language_options_through_dispatch
    client = FakeClient.new
    client.ft_create("idx", [Valkey::Search::TextField.new("title")],
                     on: :json, score: 0.5, language: "english", skip_initial_scan: true)
    assert_equal ["idx", "ON", "JSON", "SCORE", 0.5, "LANGUAGE", "english", "SKIPINITIALSCAN",
                  "SCHEMA", "title", "TEXT"],
                 client.captured_args
  end

  # ---- Cluster routing (index definitions are per-node) ----

  # On standalone no route is applied, so default routing is untouched.
  def test_ft_create_standalone_applies_no_route
    client = FakeClient.new
    client.ft_create("idx", [Valkey::Search::TextField.new("title")])
    assert_nil client.captured_route
  end

  # In cluster mode FT.CREATE must reach every primary, otherwise a query routed
  # to another shard fails with "Index with name '...' not found".
  def test_ft_create_cluster_broadcasts_to_all_primaries
    client = FakeClient.new
    client.instance_variable_set(:@cluster_mode, true)
    client.ft_create("idx", [Valkey::Search::TextField.new("title")])
    refute_nil client.captured_route
    assert_equal :all_primaries, client.captured_route.instance_variable_get(:@route_type)
  end

  def test_ft_drop_index_cluster_broadcasts_to_all_primaries
    client = FakeClient.new
    client.instance_variable_set(:@cluster_mode, true)
    client.ft_drop_index("idx")
    assert_equal ["idx"], client.captured_args
    assert_equal :all_primaries, client.captured_route.instance_variable_get(:@route_type)
  end

  # An explicit route: always wins over the broadcast default.
  def test_ft_create_explicit_route_overrides_broadcast
    client = FakeClient.new
    client.instance_variable_set(:@cluster_mode, true)
    client.ft_create("idx", [Valkey::Search::TextField.new("title")], route: Valkey::Route.random)
    assert_equal :random, client.captured_route.instance_variable_get(:@route_type)
  end
end
