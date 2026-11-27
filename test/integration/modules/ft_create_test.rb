# frozen_string_literal: true

require "test_helper"

module FtCreateTests
  def pack_float16(value)
    bits = [value].pack("f").unpack1("L")
    sign = (bits >> 16) & 0x8000
    exponent = ((bits >> 23) & 0xFF) - 127 + 15
    mantissa = (bits >> 13) & 0x3FF
    half = if value.zero?
             sign
           else
             sign | (exponent << 10) | mantissa
           end
    [half].pack("S")
  end

  def pack_bfloat16(value)
    [value].pack("f").byteslice(2, 2)
  end

  def test_create_float16_bfloat16_vector
    skip_unless_search_1_3!
    {
      "FLOAT16" => method(:pack_float16),
      "BFLOAT16" => method(:pack_bfloat16)
    }.each do |vtype, pack_one|
      index = "#{@index}_#{vtype.downcase}"
      prefix = "#{@prefix}#{vtype.downcase}:"
      @client.ft_create(index, [Valkey::Search::VectorField.flat("vec", dim: 2, metric: :l2, type: vtype)],
                        on: :hash, prefixes: [prefix])
      encode = ->(values) { values.map { |v| pack_one.call(v) }.join }
      { "0" => [0.0, 0.0], "1" => [1.0, 0.0], "2" => [2.0, 0.0] }.each do |suffix, coords|
        @client.hset("#{prefix}#{suffix}", "vec", encode.call(coords))
      end
      poll_until_indexed(@client, index, 3)

      blob = encode.call([1.0, 0.0])
      result = @client.ft_search(index, "*=>[KNN 1 @vec $blob]", params: { "blob" => blob },
                                                                 return_fields: ["__vec_score"])
      assert_equal 1, result.total_results
      doc = result.documents.first
      assert_equal "#{prefix}1", doc.key
      assert_in_delta 0.0, doc.fields["__vec_score"].to_f, 0.01
      @client.ft_drop_index(index)
    end
  end

  def test_create_filter
    skip_unless_search_1_3!
    @client.ft_create(@index, [Valkey::Search::NumericField.new("age")],
                      on: :hash, prefixes: [@prefix], filter: "@age > 18")
    @client.hset("#{@prefix}adult", "age", "25")
    @client.hset("#{@prefix}minor", "age", "10")
    poll_until_indexed(@client, @index, 1)

    result = @client.ft_search(@index, "*", no_content: true)
    assert_equal 1, result.total_results
    assert_equal Set["#{@prefix}adult"], Set.new(result.documents.map(&:key))
  end

  def test_create_sortable_unf
    skip_unless_search_1_3!
    @client.ft_create(@index, [Valkey::Search::TextField.new("title", sortable: true, unf: true)],
                      on: :hash, prefixes: [@prefix])
    info = @client.ft_info(@index)
    info = Valkey::Utils::Hashify.call(info) if info.is_a?(Array)
    attrs = info["attributes"]
    attrs = attrs.map { |a| a.is_a?(Array) ? Valkey::Utils::Hashify.call(a) : a }
    attr = attrs.first
    assert_equal "1", attr["SORTABLE"].to_s
    assert_equal "1", attr["UNF"].to_s

    @client.hset("#{@prefix}1", "title", "apple")
    @client.hset("#{@prefix}2", "title", "Banana")
    poll_until_indexed(@client, @index, 2)

    result = @client.ft_search(@index, "*", return_fields: ["title"], sort_by: "title", sort_order: :asc)
    keys = result.documents.map(&:key)
    assert_equal ["#{@prefix}2", "#{@prefix}1"], keys
  end

  def test_create_score_field_in_index_definition
    skip_unless_search_1_3!
    legacy = legacy_level?
    @client.ft_create(@index, [Valkey::Search::TextField.new("title")],
                      on: :hash, prefixes: [@prefix], score_field: "boost")
    info = @client.ft_info(@index)
    info = Valkey::Utils::Hashify.call(info) if info.is_a?(Array)
    index_def = info["index_definition"]
    index_def = Valkey::Utils::Hashify.call(index_def) if index_def.is_a?(Array)
    if legacy
      refute index_def.key?("score_field")
      assert_equal "1", index_def["default_score"].to_s
    else
      assert_equal "boost", index_def["score_field"]
      assert index_def.key?("default_score")
    end
  end

  def test_create_score_field_affects_ranking
    skip_unless_search_1_3!
    @client.ft_create(@index, [Valkey::Search::TextField.new("title")],
                      on: :hash, prefixes: [@prefix], score_field: "boost")
    @client.hset("#{@prefix}low", "title", "hello world", "boost", "1.0")
    @client.hset("#{@prefix}high", "title", "hello world", "boost", "100.0")
    poll_until_indexed(@client, @index, 2)

    result = @client.ft_search(@index, "hello", with_scores: true)
    assert_equal 2, result.total_results
    assert_equal "#{@prefix}high", result.documents.first.key
    by_key = result.documents.to_h { |d| [d.key, d.score.to_f] }
    assert_operator by_key["#{@prefix}high"], :>, by_key["#{@prefix}low"]
  end

  def test_create_no_highlight
    skip_unless_search_1_3!
    assert_equal "OK", @client.ft_create(@index, [Valkey::Search::TextField.new("title")],
                                         on: :hash, prefixes: [@prefix], no_highlight: true)
  end
end

class FtCreateStandaloneTest < Helper::SearchModuleStandaloneCase
  include FtCreateTests
end

class FtCreateClusterTest < Helper::SearchModuleClusterCase
  include FtCreateTests

  def test_multi_shard_no_hashtag
    skip_unless_search_1_3!
    @index = index = "modules_ft_create_multishard_#{SecureRandom.hex(6)}"
    @client.ft_create(index, [Valkey::Search::TextField.new("title")], on: :hash, prefixes: ["#{index}:"])
    shards = cluster_shards
    assert_operator shards.length, :>=, 2, "test requires a real multi-shard cluster"

    shards.each do |shard|
      primary = shard[:primary]
      list = @client.send_command(Valkey::RequestType::CUSTOM_COMMAND, ["FT._LIST"],
                                  route: Valkey::Route.by_address(primary["ip"], primary["port"].to_i))
      assert_includes list, index, "ft_create did not reach primary #{primary['ip']}:#{primary['port']}"
    end

    key_names = (0...30).map { |i| "#{index}:doc#{i}" }
    key_names.each { |key| @client.hset(key, "title", "doc") }
    keys_by_shard = key_names.group_by { |key| shard_for_key(shards, key) }
    assert_operator keys_by_shard.length, :>=, 2, "fixture bug: all keys hashed to one shard"

    keys_by_shard.each do |shard, keys|
      primary = shard[:primary]
      poll_node_docs(index, primary, keys.length)
    end

    result = @client.ft_search(index, "*", no_content: true, limit: [0, 100])
    observed_keys = result.documents.map(&:key)
    refute_empty observed_keys, "FT.SEARCH returned no documents"
    observed_shards = observed_keys.map { |key| shard_for_key(shards, key) }.uniq
    assert_equal 1, observed_shards.length, "a plain FT.SEARCH must be answered by a single shard"
    assert_equal Set.new(keys_by_shard.fetch(observed_shards.first)), Set.new(observed_keys)
    assert_operator result.total_results, :<, key_names.length,
                    "expected a single-shard result. If this is now the full #{key_names.length}, " \
                    "valkey-search aggregates across shards server-side; update this assertion with a " \
                    "source citation"
  end

  private

  def poll_node_docs(index, node, expected_count, timeout_secs: 10)
    route = Valkey::Route.by_address(node["ip"], node["port"].to_i)
    deadline = Time.now + timeout_secs
    loop do
      info = @client.send_command(Valkey::RequestType::CUSTOM_COMMAND, ["FT.INFO", index], route: route)
      info = Valkey::Utils::Hashify.call(info) if info.is_a?(Array)
      return if info["num_docs"].to_i >= expected_count
      raise "#{node['ip']}:#{node['port']} did not index #{expected_count} docs of #{index}" if Time.now > deadline

      sleep 0.1
    end
  end
end
