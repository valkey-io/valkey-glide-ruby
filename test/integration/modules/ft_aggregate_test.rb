# frozen_string_literal: true

require "test_helper"

module FtAggregateTests
  def test_add_scores_sortable_by_score
    skip_unless_search_1_3!
    @client.ft_create(@index, [Valkey::Search::TextField.new("title")], on: :hash, prefixes: [@prefix])
    @client.hset("#{@prefix}1", "title", "hello world")
    @client.hset("#{@prefix}2", "title", "hello there friend")
    poll_until_indexed(@client, @index, 2)

    result = @client.ft_aggregate(
      @index, "hello",
      add_scores: true, load: ["title"],
      clauses: [Valkey::Search::SortBy.new("@__score", :desc)]
    )
    assert_equal 2, result.length
    result.each { |row| assert_operator row["__score"].to_f, :>, 0 }
    scores = result.map { |row| row["__score"].to_f }
    assert_equal scores.sort.reverse, scores
  end

  def test_aggregate_reducers_to_list_first_value_random_sample
    skip_unless_search_1_3!
    @client.ft_create(
      @index,
      [Valkey::Search::TagField.new("category"), Valkey::Search::NumericField.new("price"),
       Valkey::Search::TextField.new("title")],
      on: :hash, prefixes: [@prefix]
    )
    @client.hset("#{@prefix}1", "category", "a", "price", "10", "title", "widget")
    @client.hset("#{@prefix}2", "category", "a", "price", "20", "title", "gadget")
    @client.hset("#{@prefix}3", "category", "a", "price", "10", "title", "gizmo")
    poll_until_indexed(@client, @index, 3)

    tolist = @client.ft_aggregate(
      @index, "*",
      clauses: [Valkey::Search::GroupBy.new(["@category"],
                                            reducers: [Valkey::Search::Reducer.to_list("@price", as: "prices")])]
    )
    assert_equal 1, tolist.length
    prices = tolist[0]["prices"].map { |v| v.is_a?(String) ? v : v.to_s }.sort
    assert_equal %w[10 20], prices

    first_value = @client.ft_aggregate(
      @index, "*",
      load: %w[@title @price],
      clauses: [Valkey::Search::GroupBy.new(
        ["@category"],
        reducers: [Valkey::Search::Reducer.first_value("@title", by: "@price", order: :desc, as: "most_expensive")]
      )]
    )
    assert_equal 1, first_value.length
    assert_equal "gadget", first_value[0]["most_expensive"]

    sample = @client.ft_aggregate(
      @index, "*",
      clauses: [Valkey::Search::GroupBy.new(
        ["@category"], reducers: [Valkey::Search::Reducer.random_sample("@price", 2, as: "sample")]
      )]
    )
    assert_equal 1, sample.length
    sampled = sample[0]["sample"]
    assert_kind_of Array, sampled
    assert_equal 2, sampled.length
    assert Set[sampled[0].to_s, sampled[1].to_s].subset?(Set["10", "20"])
  end

  def test_aggregate_vector_range
    skip_unless_search_1_3!
    @client.ft_create(@index, [Valkey::Search::VectorField.flat("vec", dim: 2, metric: :l2)],
                      on: :hash, prefixes: [@prefix])
    points = [[0.0, 0.0], [1.0, 0.0], [3.0, 0.0]]
    points.each_with_index { |coords, i| @client.hset("#{@prefix}#{i}", "vec", coords.pack("f*")) }
    poll_until_indexed(@client, @index, points.size)

    blob = [0.0, 0.0].pack("f*")
    result = @client.ft_aggregate(
      @index, "@vec:[VECTOR_RANGE 2 $blob]=>{$yield_distance_as: dist}",
      load: ["dist"], params: { "blob" => blob },
      clauses: [Valkey::Search::SortBy.new("@dist", :asc)]
    )
    distances = result.map { |row| row["dist"].to_f }.sort
    assert_equal [0.0, 1.0], distances
  end

  def test_aggregate_with_bicycles_data
    skip_unless_search_1_3!
    legacy = legacy_level?
    @client.ft_create(
      @index,
      [Valkey::Search::TextField.new("$.model", as: "model"),
       Valkey::Search::TagField.new("$.condition", as: "condition")],
      on: :json, prefixes: [@prefix]
    )
    @client.send_command(Valkey::RequestType::CUSTOM_COMMAND,
                         ["JSON.SET", "#{@prefix}0", "$", '{"model":"Jigger","condition":"new"}'])
    @client.send_command(Valkey::RequestType::CUSTOM_COMMAND,
                         ["JSON.SET", "#{@prefix}1", "$", '{"model":"Hillcraft","condition":"used"}'])
    @client.send_command(Valkey::RequestType::CUSTOM_COMMAND,
                         ["JSON.SET", "#{@prefix}2", "$", '{"model":"Chook","condition":"used"}'])
    poll_until_indexed(@client, @index, 3)

    result = @client.ft_aggregate(
      @index, "*",
      load: ["__key"],
      clauses: [Valkey::Search::GroupBy.new(["@condition"], reducers: [Valkey::Search::Reducer.count(as: "n")])]
    )
    column = legacy ? "$.condition" : "condition"
    by_condition = result.to_h { |row| [row[column], row["n"].to_i] }
    assert_equal({ "new" => 1, "used" => 2 }, by_condition)
  end

  def test_aggregate_with_movies_data
    skip_unless_search_1_3!
    @client.ft_create(
      @index,
      [Valkey::Search::TextField.new("title"), Valkey::Search::TagField.new("genre"),
       Valkey::Search::NumericField.new("votes")],
      on: :hash, prefixes: [@prefix]
    )
    @client.hset("#{@prefix}1", "title", "A", "genre", "Drama", "votes", "100")
    @client.hset("#{@prefix}2", "title", "B", "genre", "Action", "votes", "50")
    @client.hset("#{@prefix}3", "title", "C", "genre", "Action", "votes", "70")
    poll_until_indexed(@client, @index, 3)

    result = @client.ft_aggregate(
      @index, "*",
      load: :all,
      clauses: [
        Valkey::Search::GroupBy.new(["@genre"], reducers: [
                                      Valkey::Search::Reducer.count(as: "n"),
                                      Valkey::Search::Reducer.sum("@votes", as: "total_votes")
                                    ])
      ]
    )
    by_genre = result.to_h { |row| [row["genre"], [row["n"].to_i, row["total_votes"].to_i]] }
    assert_equal({ "Drama" => [1, 100], "Action" => [2, 120] }, by_genre)
  end

  def test_aggregate_sortby_adjacent_limit_widens_retained_rows
    skip_unless_search_1_3!
    legacy = legacy_level?
    @client.ft_create(@index, [Valkey::Search::NumericField.new("n", sortable: true)], on: :hash, prefixes: [@prefix])
    (1..20).each { |i| @client.hset("#{@prefix}d#{i}", "n", i.to_s) }
    poll_until_indexed(@client, @index, 20)

    sort_asc = Valkey::Search::SortBy.new("@n", :asc)

    no_limit = @client.ft_aggregate(@index, "*", clauses: [sort_asc])
    assert_equal 10, no_limit.length

    with_adjacent_limit = @client.ft_aggregate(@index, "*", clauses: [sort_asc, Valkey::Search::Limit.new(0, 15)])
    assert_equal(legacy ? 10 : 15, with_adjacent_limit.length)

    limit_then_sort = @client.ft_aggregate(@index, "*", clauses: [Valkey::Search::Limit.new(0, 15), sort_asc])
    assert_equal(legacy ? 10 : 15, limit_then_sort.length)

    groupby_blocks = @client.ft_aggregate(
      @index, "*",
      clauses: [sort_asc, Valkey::Search::GroupBy.new(["@n"]), Valkey::Search::Limit.new(0, 15)]
    )
    assert_equal 10, groupby_blocks.length
  end

  def test_aggregate_load_as
    skip_unless_search_1_3!
    legacy = legacy_level?
    @client.ft_create(@index, [Valkey::Search::TextField.new("title"), Valkey::Search::NumericField.new("price")],
                      on: :hash, prefixes: [@prefix])
    @client.hset("#{@prefix}1", "title", "widget", "price", "9")
    poll_until_indexed(@client, @index, 1)

    if legacy
      err = assert_raises(Valkey::CommandError) do
        @client.ft_aggregate(@index, "*", load: ["title", Valkey::Search::LoadField.new("price", as: "cost")])
      end
      assert_match(/field `AS` does not exist/, err.message)
    else
      result = @client.ft_aggregate(@index, "*", load: ["title", Valkey::Search::LoadField.new("price", as: "cost")])
      assert_equal 1, result.length
      assert_equal "widget", result[0]["title"]
      assert_equal "9", result[0]["cost"]
      refute result[0].key?("price")
    end
  end
end

class FtAggregateStandaloneTest < Helper::SearchModuleStandaloneCase
  include FtAggregateTests
end

class FtAggregateClusterTest < Helper::SearchModuleClusterCase
  include FtAggregateTests
end
