# frozen_string_literal: true

# Pure unit tests for the Phase 3 Valkey::Search aggregate API — Reducer and
# clause serialization plus AggregateOptions (TDD 6.3 / 3.1-3.5), and
# ft_aggregate dispatch (builder path serializes options, raw path forwards
# tokens verbatim).
#
# No server: builders are asserted via #to_args, and ft_aggregate against a fake
# client that captures the arguments handed to send_command.
$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require "minitest/autorun"
require "valkey/request_type"
require "valkey/search"
require "valkey/commands/vector_search_commands"

class TestSearchAggregate < Minitest::Test
  # Captures send_command so ft_aggregate can be exercised without a live server.
  class FakeClient
    include Valkey::Commands::VectorSearchCommands

    attr_reader :captured_type, :captured_args
    attr_accessor :canned_reply

    def initialize(canned_reply = [])
      @canned_reply = canned_reply
    end

    def send_command(command_type, command_args = [])
      @captured_type = command_type
      @captured_args = command_args
      @canned_reply
    end
  end

  S = Valkey::Search

  # ---- Reducer serialization ----

  def test_reducer_count_no_args
    assert_equal ["REDUCE", "COUNT", 0], S::Reducer.count.to_args
  end

  def test_reducer_count_with_alias
    assert_equal ["REDUCE", "COUNT", 0, "AS", "total"], S::Reducer.count(as: "total").to_args
  end

  def test_reducer_sum
    assert_equal ["REDUCE", "SUM", 1, "@price", "AS", "revenue"],
                 S::Reducer.sum("@price", as: "revenue").to_args
  end

  def test_reducer_count_distinct
    assert_equal ["REDUCE", "COUNT_DISTINCT", 1, "@user"],
                 S::Reducer.count_distinct("@user").to_args
  end

  def test_reducer_min_max_avg_stddev_functions
    assert_equal "MIN", S::Reducer.min("@a").function
    assert_equal "MAX", S::Reducer.max("@a").function
    assert_equal "AVG", S::Reducer.avg("@a").function
    assert_equal "STDDEV", S::Reducer.stddev("@a").function
  end

  def test_reducer_generic_constructor_upcases_function
    assert_equal ["REDUCE", "TOLIST", 1, "@tag"], S::Reducer.new(:tolist, "@tag").to_args
  end

  # ---- GroupBy clause (TDD 3.1) ----

  def test_group_by_with_reducers
    clause = S::GroupBy.new(["@category"],
                            reducers: [S::Reducer.count(as: "count"),
                                       S::Reducer.sum("@price", as: "revenue")])
    assert_equal ["GROUPBY", 1, "@category",
                  "REDUCE", "COUNT", 0, "AS", "count",
                  "REDUCE", "SUM", 1, "@price", "AS", "revenue"],
                 clause.to_args
  end

  def test_group_by_global_no_properties
    assert_equal ["GROUPBY", 0, "REDUCE", "COUNT", 0],
                 S::GroupBy.new([], reducers: [S::Reducer.count]).to_args
  end

  def test_group_by_scalar_property_coerced_to_array
    assert_equal ["GROUPBY", 1, "@category"], S::GroupBy.new("@category").to_args
  end

  def test_group_by_rejects_non_reducer
    err = assert_raises(ArgumentError) { S::GroupBy.new(["@c"], reducers: ["COUNT"]) }
    assert_match(/must be Valkey::Search::Reducer/, err.message)
  end

  # ---- SortBy clause (TDD 3.2) ----

  def test_sort_by_single_pair
    assert_equal ["SORTBY", 2, "@total", "DESC"], S::SortBy.new("@total", :desc).to_args
  end

  def test_sort_by_defaults_asc
    assert_equal ["SORTBY", 2, "@total", "ASC"], S::SortBy.new("@total").to_args
  end

  def test_sort_by_hash_multiple_keys_with_max
    clause = S::SortBy.new({ "@a" => :asc, "@b" => :desc }, max: 5)
    assert_equal ["SORTBY", 4, "@a", "ASC", "@b", "DESC", "MAX", 5], clause.to_args
  end

  def test_sort_by_array_of_pairs
    clause = S::SortBy.new([["@a", :desc], ["@b", :asc]])
    assert_equal ["SORTBY", 4, "@a", "DESC", "@b", "ASC"], clause.to_args
  end

  def test_sort_by_rejects_bad_order
    assert_raises(ArgumentError) { S::SortBy.new("@a", :sideways).to_args }
  end

  # ---- Filter / Apply / Limit clauses (TDD 3.3-3.5) ----

  def test_filter_clause
    assert_equal ["FILTER", "@total > 5"], S::Filter.new("@total > 5").to_args
  end

  def test_apply_clause
    assert_equal ["APPLY", "@price * @qty", "AS", "line_total"],
                 S::Apply.new("@price * @qty", as: "line_total").to_args
  end

  def test_limit_clause
    assert_equal ["LIMIT", 0, 10], S::Limit.new(0, 10).to_args
  end

  # ---- AggregateOptions assembly (TDD 6.3) ----

  def test_empty_aggregate_options
    assert_equal [], S::AggregateOptions.new.to_args
  end

  def test_aggregate_options_clause_order_preserved
    opts = S::AggregateOptions.new(clauses: [
                                     S::GroupBy.new(["@category"], reducers: [S::Reducer.count(as: "count")]),
                                     S::SortBy.new("@count", :desc),
                                     S::Limit.new(0, 10)
                                   ])
    assert_equal ["GROUPBY", 1, "@category", "REDUCE", "COUNT", 0, "AS", "count",
                  "SORTBY", 2, "@count", "DESC",
                  "LIMIT", 0, 10],
                 opts.to_args
  end

  def test_aggregate_options_top_level_before_clauses
    opts = S::AggregateOptions.new(verbatim: true, dialect: 2,
                                   clauses: [S::Filter.new("@x > 1")])
    assert_equal ["VERBATIM", "DIALECT", 2, "FILTER", "@x > 1"], opts.to_args
  end

  def test_aggregate_options_load_fields
    opts = S::AggregateOptions.new(load: ["@title", "@price"])
    assert_equal ["LOAD", 2, "@title", "@price"], opts.to_args
  end

  def test_aggregate_options_load_all
    assert_equal ["LOAD", "*"], S::AggregateOptions.new(load: :all).to_args
  end

  def test_aggregate_options_load_empty_emits_nothing
    assert_equal [], S::AggregateOptions.new(load: []).to_args
  end

  def test_aggregate_options_params
    opts = S::AggregateOptions.new(params: { vec: "blob", k: 5 })
    assert_equal ["PARAMS", 4, "vec", "blob", "k", 5], opts.to_args
  end

  def test_aggregate_options_slop_timeout
    opts = S::AggregateOptions.new(in_order: true, slop: 2, timeout: 500)
    assert_equal ["INORDER", "SLOP", 2, "TIMEOUT", 500], opts.to_args
  end

  def test_aggregate_options_cluster_flags_tail
    opts = S::AggregateOptions.new(clauses: [S::Filter.new("@x > 1")],
                                   shard_scope: :all_shards, consistency: :consistent)
    assert_equal ["FILTER", "@x > 1", "ALLSHARDS", "CONSISTENT"], opts.to_args
  end

  def test_aggregate_options_rejects_bad_dialect
    err = assert_raises(ArgumentError) { S::AggregateOptions.new(dialect: 3) }
    assert_match(/unsupported dialect/, err.message)
  end

  def test_aggregate_options_rejects_non_clause
    err = assert_raises(ArgumentError) { S::AggregateOptions.new(clauses: ["GROUPBY"]) }
    assert_match(/AggregateClause/, err.message)
  end

  def test_aggregate_options_rejects_bad_load
    assert_raises(ArgumentError) { S::AggregateOptions.new(load: "title").to_args }
  end

  # ---- ft_aggregate dispatch ----

  def test_ft_aggregate_builder_via_options_object
    client = FakeClient.new
    opts = S::AggregateOptions.new(clauses: [S::Limit.new(0, 5)])
    client.ft_aggregate("idx", "@price:[0 +inf]", opts)
    assert_equal Valkey::RequestType::FT_AGGREGATE, client.captured_type
    assert_equal ["idx", "@price:[0 +inf]", "LIMIT", 0, 5], client.captured_args
  end

  def test_ft_aggregate_builder_via_kwargs
    client = FakeClient.new
    client.ft_aggregate("idx", "@price:[0 +inf]",
                        clauses: [S::GroupBy.new(["@c"], reducers: [S::Reducer.count(as: "n")])])
    assert_equal ["idx", "@price:[0 +inf]", "GROUPBY", 1, "@c", "REDUCE", "COUNT", 0, "AS", "n"],
                 client.captured_args
  end

  def test_ft_aggregate_raw_args_forwarded_verbatim
    client = FakeClient.new
    client.ft_aggregate("idx", "@price:[0 +inf]", "GROUPBY", "1", "@category")
    assert_equal ["idx", "@price:[0 +inf]", "GROUPBY", "1", "@category"], client.captured_args
  end

  def test_ft_aggregate_no_options_plain
    client = FakeClient.new
    client.ft_aggregate("idx", "@price:[0 +inf]")
    assert_equal ["idx", "@price:[0 +inf]"], client.captured_args
  end

  def test_ft_aggregate_rejects_options_and_extra_positional
    client = FakeClient.new
    assert_raises(ArgumentError) do
      client.ft_aggregate("idx", "q", S::AggregateOptions.new, "extra")
    end
  end

  def test_ft_aggregate_rejects_mixed_raw_and_kwargs
    client = FakeClient.new
    assert_raises(ArgumentError) do
      client.ft_aggregate("idx", "q", "GROUPBY", clauses: [S::Filter.new("@x>1")])
    end
  end
end
