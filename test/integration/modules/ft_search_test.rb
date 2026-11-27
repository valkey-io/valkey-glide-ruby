# frozen_string_literal: true

require "test_helper"

module FtSearchTests
  def test_capability_probe_runs_without_raising
    assert_includes [true, false], @capable
    create_basic_index(@client, @index, @prefix)
    if @capable
      result = @client.ft_search(@index, "*", in_keys: ["#{@prefix}1"])
      assert_instance_of Valkey::Search::SearchResult, result
    else
      err = assert_raises(Valkey::CommandError) { @client.ft_search(@index, "*", in_keys: ["#{@prefix}1"]) }
      assert Helper::SearchCapability.inkeys_probe_error?(err.message)
    end
  end

  def test_emulate_release_level_reported_by_capable_module
    skip_unless_search_1_3!
    refute_nil @level, "a 1.3-capable module must report a search.emulate-release level"
  end

  def test_in_keys_restricts_search_to_given_keys
    skip_unless_search_1_3!
    create_basic_index(@client, @index, @prefix)
    @client.hset("#{@prefix}1", "title", "hello", "price", "1")
    @client.hset("#{@prefix}2", "title", "hello", "price", "2")
    poll_until_indexed(@client, @index, 2)

    result = @client.ft_search(@index, "*", in_keys: ["#{@prefix}1"])
    assert_equal 1, result.total_results
    assert_equal ["#{@prefix}1"], result.documents.map(&:key)
  end

  def test_in_keys_empty_array_matches_nothing
    skip_unless_search_1_3!
    create_basic_index(@client, @index, @prefix)
    @client.hset("#{@prefix}1", "title", "hello", "price", "1")
    poll_until_indexed(@client, @index, 1)

    result = @client.ft_search(@index, "*", in_keys: [])
    assert_equal 0, result.total_results
    assert_empty result.documents
  end

  def test_bare_wildcard_matches_every_document
    skip_unless_search_1_3!
    create_basic_index(@client, @index, @prefix)
    @client.hset("#{@prefix}1", "title", "hello", "price", "1")
    @client.hset("#{@prefix}2", "title", "world", "price", "2")
    @client.hset("#{@prefix}3", "title", "fizz", "price", "3")
    poll_until_indexed(@client, @index, 3)

    result = @client.ft_search(@index, "*")
    assert_equal 3, result.total_results
    assert_equal Set["#{@prefix}1", "#{@prefix}2", "#{@prefix}3"], Set.new(result.documents.map(&:key))
  end

  def test_with_scores_and_scorer
    skip_unless_search_1_3!
    create_basic_index(@client, @index, @prefix)
    @client.hset("#{@prefix}1", "title", "hello hello hello world", "price", "1")
    @client.hset("#{@prefix}2", "title", "hello there", "price", "2")
    poll_until_indexed(@client, @index, 2)

    result = @client.ft_search(@index, "hello", with_scores: true, scorer: "BM25STD")
    assert_equal 2, result.total_results
    by_key = result.documents.to_h { |d| [d.key, d] }
    by_key.each_value { |doc| assert_operator doc.score.to_f, :>, 0 }
    assert_operator by_key["#{@prefix}1"].score.to_f, :>, by_key["#{@prefix}2"].score.to_f,
                    "the document repeating the search term should score strictly higher"
    assert_equal "hello hello hello world", by_key["#{@prefix}1"].fields["title"]
  end

  def test_with_scores_and_withsortkeys_combined_shape
    skip_unless_search_1_3!
    @client.ft_create(
      @index,
      [Valkey::Search::TextField.new("title", sortable: true),
       Valkey::Search::NumericField.new("price", sortable: true)],
      on: :hash, prefixes: [@prefix]
    )
    @client.hset("#{@prefix}1", "title", "hello", "price", "10")
    @client.hset("#{@prefix}2", "title", "world", "price", "20")
    poll_until_indexed(@client, @index, 2)

    result = @client.ft_search(@index, "*", with_scores: true, sort_by: "price", with_sort_keys: true)
    assert_equal 2, result.total_results
    result.documents.each do |doc|
      refute_nil doc.score, "WITHSCORES must return a score for #{doc.key}"
      assert_operator Float(doc.score), :>=, 0
      refute_nil doc.sort_key
      assert doc.fields.key?("title")
    end
  end

  def test_scorer_tfidf_rejected
    skip_unless_search_1_3!
    create_basic_index(@client, @index, @prefix)
    @client.hset("#{@prefix}1", "title", "hello world", "price", "1")
    poll_until_indexed(@client, @index, 1)

    err = assert_raises(Valkey::CommandError) { @client.ft_search(@index, "hello", with_scores: true, scorer: "TFIDF") }
    assert_match(/SCORER/, err.message)
  end

  def test_count_option_emits_limit_zero_zero_and_returns_total_only
    skip_unless_search_1_3!
    create_basic_index(@client, @index, @prefix)
    @client.hset("#{@prefix}1", "title", "hello", "price", "1")
    @client.hset("#{@prefix}2", "title", "hello", "price", "2")
    poll_until_indexed(@client, @index, 2)

    result = @client.ft_search(@index, "*", count: true)
    assert_equal 2, result.total_results
    assert_empty result.documents
  end

  def test_search_vector_range
    skip_unless_search_1_3!
    @client.ft_create(
      @index,
      [Valkey::Search::VectorField.flat("vec", dim: 2, metric: :l2), Valkey::Search::TagField.new("category")],
      on: :hash, prefixes: [@prefix]
    )
    points = { "0" => [[0.0, 0.0], "a"], "1" => [[1.0, 0.0], "b"], "2" => [[2.0, 0.0], "a"] }
    points.each do |suffix, (coords, cat)|
      @client.hset("#{@prefix}#{suffix}", "vec", coords.pack("f*"), "category", cat)
    end
    poll_until_indexed(@client, @index, points.size)

    blob = [0.0, 0.0].pack("f*")
    result = @client.ft_search(@index, "@vec:[VECTOR_RANGE 1.5 $blob]", params: { "blob" => blob }, no_content: true)
    assert_equal 2, result.total_results
    assert_equal Set["#{@prefix}0", "#{@prefix}1"], Set.new(result.documents.map(&:key))
  end
end

class FtSearchStandaloneTest < Helper::SearchModuleStandaloneCase
  include FtSearchTests

  def test_search_limit_pagination
    skip_unless_search_1_3!
    @client.ft_create(@index, [Valkey::Search::NumericField.new("n", sortable: true)], on: :hash, prefixes: [@prefix])
    (1..10).each { |i| @client.hset("#{@prefix}d#{i}", "n", i.to_s) }
    poll_until_indexed(@client, @index, 10)

    page1 = @client.ft_search(@index, "*", limit: [0, 3])
    assert_equal 10, page1.total_results
    assert_equal 3, page1.documents.length

    page2 = @client.ft_search(@index, "*", limit: [3, 3])
    assert_equal 10, page2.total_results
    assert_equal 3, page2.documents.length
    refute_equal Set.new(page1.documents.map(&:key)), Set.new(page2.documents.map(&:key))
  end
end

class FtSearchClusterTest < Helper::SearchModuleClusterCase
  include FtSearchTests
end
