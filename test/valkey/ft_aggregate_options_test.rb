# frozen_string_literal: true

require "test_helper"

class TestFtAggregateOptions < Minitest::Test
  # --- Reducer ---

  def test_reducer_count
    r = Valkey::Search::Reducer.new("COUNT", [], name: "count")
    assert_equal ["REDUCE", "COUNT", "0", "AS", "count"], r.to_args
  end

  def test_reducer_sum
    r = Valkey::Search::Reducer.new("SUM", ["@price"], name: "total")
    assert_equal ["REDUCE", "SUM", "1", "@price", "AS", "total"], r.to_args
  end

  def test_reducer_avg
    r = Valkey::Search::Reducer.new("AVG", ["@score"], name: "avg_score")
    assert_equal ["REDUCE", "AVG", "1", "@score", "AS", "avg_score"], r.to_args
  end

  def test_reducer_min_max
    r = Valkey::Search::Reducer.new("MIN", ["@price"], name: "cheapest")
    assert_equal ["REDUCE", "MIN", "1", "@price", "AS", "cheapest"], r.to_args
  end

  def test_reducer_no_name
    r = Valkey::Search::Reducer.new("COUNT", [])
    assert_equal ["REDUCE", "COUNT", "0"], r.to_args
  end

  # --- GroupBy ---

  def test_groupby_single_property
    gb = Valkey::Search::GroupBy.new(["@category"])
    assert_equal ["GROUPBY", "1", "@category"], gb.to_args
  end

  def test_groupby_multiple_properties
    gb = Valkey::Search::GroupBy.new(["@category", "@brand"])
    assert_equal ["GROUPBY", "2", "@category", "@brand"], gb.to_args
  end

  def test_groupby_with_reducers
    gb = Valkey::Search::GroupBy.new(["@category"],
                                    reducers: [
                                      Valkey::Search::Reducer.new("COUNT", [], name: "count"),
                                      Valkey::Search::Reducer.new("SUM", ["@price"], name: "total")
                                    ])
    expected = ["GROUPBY", "1", "@category",
                "REDUCE", "COUNT", "0", "AS", "count",
                "REDUCE", "SUM", "1", "@price", "AS", "total"]
    assert_equal expected, gb.to_args
  end

  # --- SortProperty ---

  def test_sort_property_asc
    sp = Valkey::Search::SortProperty.new("@price", :asc)
    assert_equal ["@price", "ASC"], sp.to_args
  end

  def test_sort_property_desc
    sp = Valkey::Search::SortProperty.new("@price", :desc)
    assert_equal ["@price", "DESC"], sp.to_args
  end

  # --- SortBy ---

  def test_sortby_single
    sb = Valkey::Search::SortBy.new([Valkey::Search::SortProperty.new("@price", :asc)])
    assert_equal ["SORTBY", "2", "@price", "ASC"], sb.to_args
  end

  def test_sortby_multiple
    sb = Valkey::Search::SortBy.new([
                                      Valkey::Search::SortProperty.new("@category", :asc),
                                      Valkey::Search::SortProperty.new("@price", :desc)
                                    ])
    assert_equal ["SORTBY", "4", "@category", "ASC", "@price", "DESC"], sb.to_args
  end

  def test_sortby_with_max
    sb = Valkey::Search::SortBy.new(
      [Valkey::Search::SortProperty.new("@price", :asc)], max: 10
    )
    assert_equal ["SORTBY", "2", "@price", "ASC", "MAX", "10"], sb.to_args
  end

  # --- Apply ---

  def test_apply
    a = Valkey::Search::Apply.new("@price * 1.1", name: "price_with_tax")
    assert_equal ["APPLY", "@price * 1.1", "AS", "price_with_tax"], a.to_args
  end

  # --- Filter ---

  def test_filter
    f = Valkey::Search::Filter.new("@count > 5")
    assert_equal ["FILTER", "@count > 5"], f.to_args
  end

  # --- AggregateLimit ---

  def test_aggregate_limit
    l = Valkey::Search::AggregateLimit.new(offset: 0, count: 10)
    assert_equal ["LIMIT", "0", "10"], l.to_args
  end

  def test_aggregate_limit_with_offset
    l = Valkey::Search::AggregateLimit.new(offset: 20, count: 5)
    assert_equal ["LIMIT", "20", "5"], l.to_args
  end

  # --- FtAggregateOptions ---

  def test_empty_options
    opts = Valkey::Search::FtAggregateOptions.new
    assert_equal [], opts.to_args
  end

  def test_verbatim
    opts = Valkey::Search::FtAggregateOptions.new(verbatim: true)
    assert_equal ["VERBATIM"], opts.to_args
  end

  def test_inorder
    opts = Valkey::Search::FtAggregateOptions.new(inorder: true)
    assert_equal ["INORDER"], opts.to_args
  end

  def test_slop
    opts = Valkey::Search::FtAggregateOptions.new(slop: 3)
    assert_equal ["SLOP", "3"], opts.to_args
  end

  def test_load_all
    opts = Valkey::Search::FtAggregateOptions.new(load_all: true)
    assert_equal ["LOAD", "*"], opts.to_args
  end

  def test_load_fields
    opts = Valkey::Search::FtAggregateOptions.new(load_fields: ["@price", "@title"])
    assert_equal ["LOAD", "2", "@price", "@title"], opts.to_args
  end

  def test_timeout
    opts = Valkey::Search::FtAggregateOptions.new(timeout: 5000)
    assert_equal ["TIMEOUT", "5000"], opts.to_args
  end

  def test_params
    opts = Valkey::Search::FtAggregateOptions.new(params: { "threshold" => "100" })
    assert_equal ["PARAMS", "2", "threshold", "100"], opts.to_args
  end

  def test_dialect
    opts = Valkey::Search::FtAggregateOptions.new(dialect: 2)
    assert_equal ["DIALECT", "2"], opts.to_args
  end

  def test_clauses_groupby
    opts = Valkey::Search::FtAggregateOptions.new(
      clauses: [
        Valkey::Search::GroupBy.new(["@category"],
                                   reducers: [Valkey::Search::Reducer.new("COUNT", [], name: "count")])
      ]
    )
    expected = ["GROUPBY", "1", "@category", "REDUCE", "COUNT", "0", "AS", "count"]
    assert_equal expected, opts.to_args
  end

  def test_clauses_pipeline
    opts = Valkey::Search::FtAggregateOptions.new(
      clauses: [
        Valkey::Search::GroupBy.new(["@category"],
                                   reducers: [Valkey::Search::Reducer.new("COUNT", [], name: "count")]),
        Valkey::Search::SortBy.new([Valkey::Search::SortProperty.new("@count", :desc)]),
        Valkey::Search::AggregateLimit.new(offset: 0, count: 5)
      ]
    )
    expected = [
      "GROUPBY", "1", "@category", "REDUCE", "COUNT", "0", "AS", "count",
      "SORTBY", "2", "@count", "DESC",
      "LIMIT", "0", "5"
    ]
    assert_equal expected, opts.to_args
  end

  def test_combined_full
    opts = Valkey::Search::FtAggregateOptions.new(
      verbatim: true,
      load_fields: ["@price"],
      timeout: 3000,
      params: { "min" => "10" },
      clauses: [
        Valkey::Search::Filter.new("@price > 10"),
        Valkey::Search::GroupBy.new(["@category"],
                                   reducers: [Valkey::Search::Reducer.new("SUM", ["@price"], name: "total")]),
        Valkey::Search::Apply.new("@total * 0.9", name: "discounted"),
        Valkey::Search::SortBy.new([Valkey::Search::SortProperty.new("@discounted", :desc)], max: 3)
      ],
      dialect: 2
    )
    expected = [
      "VERBATIM",
      "LOAD", "1", "@price",
      "TIMEOUT", "3000",
      "PARAMS", "2", "min", "10",
      "FILTER", "@price > 10",
      "GROUPBY", "1", "@category", "REDUCE", "SUM", "1", "@price", "AS", "total",
      "APPLY", "@total * 0.9", "AS", "discounted",
      "SORTBY", "2", "@discounted", "DESC", "MAX", "3",
      "DIALECT", "2"
    ]
    assert_equal expected, opts.to_args
  end

  def test_ordering_load_before_clauses
    opts = Valkey::Search::FtAggregateOptions.new(
      load_fields: ["@x"],
      clauses: [Valkey::Search::Filter.new("@x > 0")],
      dialect: 2
    )
    args = opts.to_args
    assert args.index("LOAD") < args.index("FILTER")
    assert args.index("FILTER") < args.index("DIALECT")
  end
end
