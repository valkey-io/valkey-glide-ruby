# frozen_string_literal: true

require "test_helper"

class TestFtSearchOptions < Minitest::Test
  # --- FtSearchLimit ---

  def test_search_limit_to_args
    limit = Valkey::Search::FtSearchLimit.new(offset: 5, count: 20)
    assert_equal ["LIMIT", "5", "20"], limit.to_args
  end

  # --- ReturnField ---

  def test_return_field_basic
    field = Valkey::Search::ReturnField.new("title")
    assert_equal ["title"], field.to_args
  end

  def test_return_field_with_alias
    field = Valkey::Search::ReturnField.new("$.title", field_alias: "title")
    assert_equal ["$.title", "AS", "title"], field.to_args
  end

  # --- FtSearchOptions ---

  def test_empty_options
    opts = Valkey::Search::FtSearchOptions.new
    assert_equal [], opts.to_args
  end

  def test_nocontent
    opts = Valkey::Search::FtSearchOptions.new(nocontent: true)
    assert_equal ["NOCONTENT"], opts.to_args
  end

  def test_verbatim
    opts = Valkey::Search::FtSearchOptions.new(verbatim: true)
    assert_equal ["VERBATIM"], opts.to_args
  end

  def test_inorder
    opts = Valkey::Search::FtSearchOptions.new(inorder: true)
    assert_equal ["INORDER"], opts.to_args
  end

  def test_slop
    opts = Valkey::Search::FtSearchOptions.new(slop: 2)
    assert_equal ["SLOP", "2"], opts.to_args
  end

  def test_return_fields
    opts = Valkey::Search::FtSearchOptions.new(
      return_fields: [
        Valkey::Search::ReturnField.new("title"),
        Valkey::Search::ReturnField.new("price")
      ]
    )
    assert_equal ["RETURN", "2", "title", "price"], opts.to_args
  end

  def test_return_fields_with_alias
    opts = Valkey::Search::FtSearchOptions.new(
      return_fields: [
        Valkey::Search::ReturnField.new("$.title", field_alias: "title"),
        Valkey::Search::ReturnField.new("price")
      ]
    )
    # "$.title" + "AS" + "title" = 3 tokens, "price" = 1 token, total = 4
    assert_equal ["RETURN", "4", "$.title", "AS", "title", "price"], opts.to_args
  end

  def test_sortby
    opts = Valkey::Search::FtSearchOptions.new(sortby: "price")
    assert_equal ["SORTBY", "price"], opts.to_args
  end

  def test_sortby_with_order
    opts = Valkey::Search::FtSearchOptions.new(sortby: "price", sortby_order: :asc)
    assert_equal ["SORTBY", "price", "ASC"], opts.to_args
  end

  def test_sortby_desc
    opts = Valkey::Search::FtSearchOptions.new(sortby: "price", sortby_order: :desc)
    assert_equal ["SORTBY", "price", "DESC"], opts.to_args
  end

  def test_withsortkeys
    opts = Valkey::Search::FtSearchOptions.new(sortby: "price", withsortkeys: true)
    assert_equal ["SORTBY", "price", "WITHSORTKEYS"], opts.to_args
  end

  def test_timeout
    opts = Valkey::Search::FtSearchOptions.new(timeout: 5000)
    assert_equal ["TIMEOUT", "5000"], opts.to_args
  end

  def test_params
    opts = Valkey::Search::FtSearchOptions.new(params: { "vec" => "binary_data" })
    assert_equal ["PARAMS", "2", "vec", "binary_data"], opts.to_args
  end

  def test_params_multiple
    opts = Valkey::Search::FtSearchOptions.new(params: { "vec" => "data1", "k" => "5" })
    assert_equal ["PARAMS", "4", "vec", "data1", "k", "5"], opts.to_args
  end

  def test_limit
    opts = Valkey::Search::FtSearchOptions.new(
      limit: Valkey::Search::FtSearchLimit.new(offset: 0, count: 10)
    )
    assert_equal ["LIMIT", "0", "10"], opts.to_args
  end

  def test_count
    opts = Valkey::Search::FtSearchOptions.new(count: true)
    assert_equal ["COUNT"], opts.to_args
  end

  def test_dialect
    opts = Valkey::Search::FtSearchOptions.new(dialect: 2)
    assert_equal ["DIALECT", "2"], opts.to_args
  end

  def test_shard_scope_allshards
    opts = Valkey::Search::FtSearchOptions.new(shard_scope: :allshards)
    assert_equal ["ALLSHARDS"], opts.to_args
  end

  def test_shard_scope_someshards
    opts = Valkey::Search::FtSearchOptions.new(shard_scope: :someshards)
    assert_equal ["SOMESHARDS"], opts.to_args
  end

  def test_consistency_consistent
    opts = Valkey::Search::FtSearchOptions.new(consistency: :consistent)
    assert_equal ["CONSISTENT"], opts.to_args
  end

  def test_consistency_inconsistent
    opts = Valkey::Search::FtSearchOptions.new(consistency: :inconsistent)
    assert_equal ["INCONSISTENT"], opts.to_args
  end

  def test_combined_typical_search
    opts = Valkey::Search::FtSearchOptions.new(
      verbatim: true,
      sortby: "price", sortby_order: :asc,
      limit: Valkey::Search::FtSearchLimit.new(offset: 0, count: 10),
      return_fields: [Valkey::Search::ReturnField.new("title"),
                      Valkey::Search::ReturnField.new("price")]
    )
    expected = ["VERBATIM", "RETURN", "2", "title", "price",
                "SORTBY", "price", "ASC", "LIMIT", "0", "10"]
    assert_equal expected, opts.to_args
  end

  def test_combined_vector_search
    opts = Valkey::Search::FtSearchOptions.new(
      params: { "vec" => "blob" },
      dialect: 2,
      limit: Valkey::Search::FtSearchLimit.new(offset: 0, count: 5)
    )
    expected = ["PARAMS", "2", "vec", "blob", "LIMIT", "0", "5", "DIALECT", "2"]
    assert_equal expected, opts.to_args
  end

  def test_ordering_matches_spec
    # Verify shard/consistency come first, then NOCONTENT/VERBATIM/INORDER/SLOP,
    # then RETURN, SORTBY, WITHSORTKEYS, TIMEOUT, PARAMS, LIMIT, COUNT, DIALECT
    opts = Valkey::Search::FtSearchOptions.new(
      shard_scope: :allshards,
      consistency: :consistent,
      nocontent: true,
      verbatim: true,
      inorder: true,
      slop: 1,
      sortby: "price", sortby_order: :desc,
      withsortkeys: true,
      timeout: 1000,
      params: { "x" => "1" },
      limit: Valkey::Search::FtSearchLimit.new(offset: 0, count: 5),
      count: true,
      dialect: 2
    )
    args = opts.to_args
    # Check ordering of key tokens
    assert args.index("ALLSHARDS") < args.index("CONSISTENT")
    assert args.index("CONSISTENT") < args.index("NOCONTENT")
    assert args.index("NOCONTENT") < args.index("VERBATIM")
    assert args.index("VERBATIM") < args.index("INORDER")
    assert args.index("INORDER") < args.index("SLOP")
    assert args.index("SLOP") < args.index("SORTBY")
    assert args.index("SORTBY") < args.index("WITHSORTKEYS")
    assert args.index("WITHSORTKEYS") < args.index("TIMEOUT")
    assert args.index("TIMEOUT") < args.index("PARAMS")
    assert args.index("PARAMS") < args.index("LIMIT")
    assert args.index("LIMIT") < args.index("COUNT")
    assert args.index("COUNT") < args.index("DIALECT")
  end

  def test_withsortkeys_accessor
    opts = Valkey::Search::FtSearchOptions.new(sortby: "price", withsortkeys: true)
    assert_equal true, opts.withsortkeys

    opts2 = Valkey::Search::FtSearchOptions.new(sortby: "price")
    assert_equal false, opts2.withsortkeys
  end
end
