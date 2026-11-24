# frozen_string_literal: true

require "test_helper"

module FtHybridTests
  def test_hybrid_basic_query
    skip_unless_search_1_3!
    create_hybrid_index(@client, @index, @prefix)
    result = @client.ft_hybrid(
      @index,
      Valkey::Search::HybridSearchArm.new("hello"),
      Valkey::Search::HybridVsimArm.new("vec", [10.0, 10.0].pack("f*"), k: 5)
    )
    assert_equal 2, result.length
    keys = result.map { |row| row["__key"] }
    assert_equal Set["#{@prefix}text_winner", "#{@prefix}vector_winner"], Set.new(keys)
    result.each { |row| assert row.key?("__score") }
  end

  def test_hybrid_filter_immediately_after_vsim_arm_is_not_claimed_as_vsim_prefilter
    skip_unless_search_1_3!
    create_hybrid_index(@client, @index, @prefix)

    rows = @client.ft_hybrid(
      @index,
      Valkey::Search::HybridSearchArm.new("goodbye", yield_score_as: "ss"),
      Valkey::Search::HybridVsimArm.new("vec", [10.0, 10.0].pack("f*"), k: 5),
      Valkey::Search::HybridOptions.new(clauses: [Valkey::Search::Filter.new("@ss > 0")])
    )
    assert_equal 1, rows.length
    assert_equal "#{@prefix}vector_winner", rows[0]["__key"]
  end

  def test_hybrid_combine_methods_fuse_results
    skip_unless_search_1_3!
    create_hybrid_index(@client, @index, @prefix)

    linear_text = @client.ft_hybrid(
      @index,
      Valkey::Search::HybridSearchArm.new("hello", yield_score_as: "ss"),
      Valkey::Search::HybridVsimArm.new("vec", [10.0, 10.0].pack("f*"), k: 5, yield_score_as: "vs"),
      Valkey::Search::HybridOptions.new(combine: Valkey::Search::HybridCombine.linear(alpha: 1.0, beta: 0.0))
    )
    assert_equal "#{@prefix}text_winner", linear_text[0]["__key"]

    linear_vec = @client.ft_hybrid(
      @index,
      Valkey::Search::HybridSearchArm.new("hello", yield_score_as: "ss"),
      Valkey::Search::HybridVsimArm.new("vec", [10.0, 10.0].pack("f*"), k: 5, yield_score_as: "vs"),
      Valkey::Search::HybridOptions.new(combine: Valkey::Search::HybridCombine.linear(alpha: 0.0, beta: 1.0))
    )
    assert_equal "#{@prefix}vector_winner", linear_vec[0]["__key"]
  end

  def test_hybrid_vector_inline_bytes_and_param_reference
    skip_unless_search_1_3!
    create_hybrid_index(@client, @index, @prefix)
    vec = [10.0, 10.0].pack("f*")

    inline = @client.ft_hybrid(@index, Valkey::Search::HybridSearchArm.new("hello"),
                               Valkey::Search::HybridVsimArm.new("vec", vec, k: 1, yield_score_as: "vs"))
    param = @client.ft_hybrid(
      @index, Valkey::Search::HybridSearchArm.new("hello"),
      Valkey::Search::HybridVsimArm.new("vec", "$myvec", k: 1, yield_score_as: "vs"),
      Valkey::Search::HybridOptions.new(params: { "myvec" => vec })
    )
    inline_keys = Set.new(inline.map { |row| row["__key"] })
    param_keys = Set.new(param.map { |row| row["__key"] })
    assert_equal inline_keys, param_keys
    [inline, param].each do |result|
      with_vs = result.select { |row| row.key?("vs") }
      assert_equal 1, with_vs.length
      assert_equal "#{@prefix}vector_winner", with_vs.first["__key"]
    end
  end

  def test_hybrid_vsim_filter_with_policy
    skip_unless_search_1_3!
    create_hybrid_index(@client, @index, @prefix)
    %w[ADHOC BATCHES].each do |policy|
      result = @client.ft_hybrid(
        @index,
        Valkey::Search::HybridSearchArm.new("nonexistentterm12345"),
        Valkey::Search::HybridVsimArm.new(
          "vec", [10.0, 10.0].pack("f*"), k: 5,
                                          filter: Valkey::Search::HybridVsimFilter.new("@title:hello", policy: policy)
        )
      )
      assert_equal 1, result.length
      assert_equal "#{@prefix}text_winner", result[0]["__key"]
    end
  end

  def test_hybrid_per_arm_and_combine_yield_score_as_columns
    skip_unless_search_1_3!
    create_hybrid_index(@client, @index, @prefix)
    result = @client.ft_hybrid(
      @index,
      Valkey::Search::HybridSearchArm.new("hello", yield_score_as: "ss"),
      Valkey::Search::HybridVsimArm.new("vec", [10.0, 10.0].pack("f*"), k: 5, yield_score_as: "vs"),
      Valkey::Search::HybridOptions.new(combine: Valkey::Search::HybridCombine.rrf(yield_score_as: "fused"))
    )
    assert_equal 2, result.length
    result.each do |row|
      assert row.key?("vs")
      assert row.key?("fused")
      refute row.key?("__score")
    end
    by_key = result.to_h { |row| [row["__key"], row] }
    assert by_key["#{@prefix}text_winner"].key?("ss")
    refute by_key["#{@prefix}vector_winner"].key?("ss")
  end

  def test_hybrid_without_k_uses_engine_default
    skip_unless_search_1_3!
    index = "#{@index}_defaultk"
    prefix = "#{@prefix}defaultk:"
    @client.ft_create(index,
                      [Valkey::Search::TextField.new("title"),
                       Valkey::Search::VectorField.flat("vec", dim: 2, metric: :l2)],
                      on: :hash, prefixes: [prefix])
    15.times { |i| @client.hset("#{prefix}d#{i}", "title", "goodbye", "vec", [i.to_f, i.to_f].pack("f*")) }
    poll_until_indexed(@client, index, 15)

    result = @client.ft_hybrid(index, Valkey::Search::HybridSearchArm.new("nonexistentterm12345"),
                               Valkey::Search::HybridVsimArm.new("vec", [1.0, 1.0].pack("f*")))
    assert_equal 10, result.length
  end

  def test_hybrid_localonly_accepted
    skip_unless_search_1_3!
    create_hybrid_index(@client, @index, @prefix)
    result = @client.ft_hybrid(
      @index, Valkey::Search::HybridSearchArm.new("hello"),
      Valkey::Search::HybridVsimArm.new("vec", [10.0, 10.0].pack("f*"), k: 5),
      Valkey::Search::HybridOptions.new(local_only: true)
    )
    assert_equal 2, result.length
  end

  def test_hybrid_inside_multi_exec_rejected
    skip_unless_search_1_3!
    create_hybrid_index(@client, @index, @prefix)
    err = assert_raises(ArgumentError) do
      @client.multi do |tx|
        tx.ft_hybrid(@index, Valkey::Search::HybridSearchArm.new("hello"),
                     Valkey::Search::HybridVsimArm.new("vec", [10.0, 10.0].pack("f*"), k: 5))
      end
    end
    assert_match(%r{not supported inside pipelined/multi}, err.message)
  end

  def test_hybrid_vsim_range_rejected
    skip_unless_search_1_3!
    create_hybrid_index(@client, @index, @prefix)
    blob = [1.0, 2.0].pack("f*")
    err = assert_raises(Valkey::CommandError) do
      @client.send_command(Valkey::RequestType::CUSTOM_COMMAND, [
                             "FT.HYBRID", @index, "SEARCH", "hello", "VSIM", "@vec", "$blob",
                             "RANGE", "2", "RADIUS", "5.0", "PARAMS", "2", "blob", blob
                           ])
    end
    assert_match(/RANGE/, err.message)
  end
end

class FtHybridStandaloneTest < Helper::SearchModuleStandaloneCase
  include FtHybridTests
end

class FtHybridClusterTest < Helper::SearchModuleClusterCase
  include FtHybridTests

  def test_hybrid_with_cursor_prefer_replica_client_paged_to_exhaustion
    skip_unless_search_1_3!
    create_hybrid_index(@client, @index, @prefix)

    prefer_replica = Valkey.new(cluster_mode: true, nodes: Helper::ModuleClient.cluster_addresses,
                                timeout: TIMEOUT, read_from: Valkey::ReadFrom::PREFER_REPLICA)
    begin
      total = 0
      seen = Set.new
      page = prefer_replica.ft_hybrid(
        @index, Valkey::Search::HybridSearchArm.new("*"),
        Valkey::Search::HybridVsimArm.new("vec", [10.0, 10.0].pack("f*"), k: 5),
        Valkey::Search::HybridOptions.new(with_cursor: Valkey::Search::WithCursor.new(count: 1))
      )
      rows, cursor_id = page
      total += rows.length
      seen.merge(rows.map { |row| row["__key"] })
      pages_read = 1
      while cursor_id != 0
        rows, cursor_id = prefer_replica.ft_cursor_read(@index, cursor_id)
        total += rows.length
        seen.merge(rows.map { |row| row["__key"] })
        pages_read += 1
        raise "paging did not terminate" if pages_read > 10
      end
      assert_equal 2, total
      assert_equal Set["#{@prefix}text_winner", "#{@prefix}vector_winner"], seen
    ensure
      prefer_replica&.close
    end
  end
end
