# frozen_string_literal: true

require "test_helper"

class TestFtInfoOptions < Minitest::Test
  def test_empty_options
    opts = Valkey::Search::FtInfoOptions.new
    assert_equal [], opts.to_args
  end

  def test_scope_local
    opts = Valkey::Search::FtInfoOptions.new(scope: :local)
    assert_equal ["LOCAL"], opts.to_args
  end

  def test_scope_primary
    opts = Valkey::Search::FtInfoOptions.new(scope: :primary)
    assert_equal ["PRIMARY"], opts.to_args
  end

  def test_scope_cluster
    opts = Valkey::Search::FtInfoOptions.new(scope: :cluster)
    assert_equal ["CLUSTER"], opts.to_args
  end

  def test_shard_scope_allshards
    opts = Valkey::Search::FtInfoOptions.new(shard_scope: :allshards)
    assert_equal ["ALLSHARDS"], opts.to_args
  end

  def test_shard_scope_someshards
    opts = Valkey::Search::FtInfoOptions.new(shard_scope: :someshards)
    assert_equal ["SOMESHARDS"], opts.to_args
  end

  def test_consistency_consistent
    opts = Valkey::Search::FtInfoOptions.new(consistency: :consistent)
    assert_equal ["CONSISTENT"], opts.to_args
  end

  def test_consistency_inconsistent
    opts = Valkey::Search::FtInfoOptions.new(consistency: :inconsistent)
    assert_equal ["INCONSISTENT"], opts.to_args
  end

  def test_combined_scope_and_shard
    opts = Valkey::Search::FtInfoOptions.new(scope: :cluster, shard_scope: :someshards)
    assert_equal ["CLUSTER", "SOMESHARDS"], opts.to_args
  end

  def test_combined_all
    opts = Valkey::Search::FtInfoOptions.new(
      scope: :primary, shard_scope: :allshards, consistency: :consistent
    )
    assert_equal ["PRIMARY", "ALLSHARDS", "CONSISTENT"], opts.to_args
  end

  def test_ordering
    opts = Valkey::Search::FtInfoOptions.new(
      scope: :cluster, shard_scope: :someshards, consistency: :inconsistent
    )
    args = opts.to_args
    assert args.index("CLUSTER") < args.index("SOMESHARDS")
    assert args.index("SOMESHARDS") < args.index("INCONSISTENT")
  end
end
