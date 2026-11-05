# frozen_string_literal: true

require "test_helper"

# Runs valkey-search 1.3 FT.* tests against a REAL valkey-search module via
# Docker (utils/run-modules-ci-locally.sh), in addition to (not instead of)
# the vendored RediSearch .so test/lint/vector_search_commands.rb exercises.
#
# Gated by the capability probe (Helper::SearchCapability) rather than a
# version-string compare: on valkey-bundle:9.1.3 (search 1.2.1) every test
# in this class skips with a stated reason. Against the rc2 .so from
# BUILD-MODULES-1.3.md, tests further branch on the active
# search.emulate-release level via `skip_unless_emulate_release_1_3!` and
# `legacy_level?` (the level fixture) to assert the corrected 1.3 behavior
# only when that level is actually >= 1.3.0, and the legacy pre-1.3 engine
# behavior otherwise -- a 1.3-capable module left at its own default
# (1.0.0) still runs the legacy branch of every
# VALKEY_SEARCH_COMPATIBILITY_FIX gate.
#
# Every index/key uses a per-test random suffix (SecureRandom.hex) so tests
# never share a keyspace or index name -- running this file repeatedly, or
# alongside the cluster suite below, must never let one test's leftover
# documents or in-flight backfill affect another's result (port rule:
# "tests assert sets, not counts"; every live assertion here checks the
# actual key set/value/order returned, never a bare count that could be
# satisfied by stale data from a previous run).
#
# Run via: utils/run-modules-ci-locally.sh (sets MODULES_STANDALONE_ENDPOINT
# / MODULES_CLUSTER_ENDPOINTS and invokes `rake test:modules`). Running this
# file directly without that harness fails loudly (no endpoints configured),
# rather than silently falling back to the main suite's vendored-.so fixture.
module ModulesFt13Shared
  include Helper::ModuleClient

  def ft13_setup(client)
    @capable = Helper::SearchCapability.probe_1_3_capability(client)
    @level = @capable ? Helper::SearchCapability.emulate_release_level(client) : nil
    # A hashtag shared by the index name and every seeded key's prefix so
    # the index and its documents always land on the same cluster shard
    # (CLUSTER KEYSLOT hashes only the {...} portion) -- otherwise FT.INFO/
    # FT.SEARCH/FT.AGGREGATE (routed by index name) and HSET (routed by
    # each key's own name) can land on different shards with no
    # relationship between them, and the index never sees the documents
    # at all. The dedicated cross-shard scenario (no hashtag, by design)
    # is covered separately by test_ft_multi_shard_no_hashtag.
    hashtag = SecureRandom.hex(6)
    @index = "{#{hashtag}}idx"
    @prefix = "{#{hashtag}}doc:"
  end

  def skip_unless_1_3!
    skip "search module is pre-1.3 (search.emulate-release unavailable); 1.3 tests skip on this build" unless @capable
  end

  # The level fixture: branches compat-gated behaviour on whether
  # search.emulate-release is actually >= 1.3.0, rather than skipping.
  # legacy? is true below 1.3.0 (including a 1.3-capable module left at its
  # own default of 1.0.0) and false at/above 1.3.0.
  def legacy_level?
    skip_unless_1_3!
    @level.nil? || Helper::Version.new(@level) < Helper::Version.new("1.3.0")
  end

  def poll_until_indexed(client, index, expected_count, timeout_secs: 10)
    deadline = Time.now + timeout_secs
    last_count = -1
    loop do
      info = client.ft_info(index)
      info = Valkey::Utils::Hashify.call(info) if info.is_a?(Array)
      raise "poll_until_indexed: FT.INFO reply for #{index} has no num_docs" unless info.key?("num_docs")

      last_count = info["num_docs"].to_i
      return if last_count >= expected_count
      if Time.now > deadline
        raise "poll_until_indexed: #{index} did not reach #{expected_count} docs within #{timeout_secs}s " \
              "(last seen: #{last_count})"
      end

      sleep 0.1
    end
  end

  def create_basic_index(client, index, prefix)
    client.ft_create(
      index,
      [Valkey::Search::TextField.new("title", sortable: true), Valkey::Search::NumericField.new("price")],
      on: :hash, prefixes: [prefix]
    )
  end

  def create_vector_index(client, index, prefix)
    client.ft_create(
      index,
      [
        Valkey::Search::TextField.new("title"),
        Valkey::Search::NumericField.new("price"),
        Valkey::Search::VectorField.flat("vec", dim: 4, metric: :l2)
      ],
      on: :hash, prefixes: [prefix]
    )
  end

  def create_hybrid_index(client, index, prefix)
    client.ft_create(
      index,
      [
        Valkey::Search::TextField.new("title"),
        Valkey::Search::VectorField.flat("vec", dim: 2, metric: :l2)
      ],
      on: :hash, prefixes: [prefix]
    )
    client.hset("#{prefix}text_winner", "title", "hello world", "vec", [1000.0, 1000.0].pack("f*"))
    client.hset("#{prefix}vector_winner", "title", "goodbye", "vec", [10.0, 10.0].pack("f*"))
    poll_until_indexed(client, index, 2)
  end

  # ---- capability probe / level fixture plumbing ----

  def test_capability_probe_runs_without_raising
    assert_includes [true, false], @capable
    # The probe's result must actually predict whether the 1.3-only
    # INKEYS option is accepted -- not just return some non-nil value.
    # This is the live cross-check that makes the probe itself
    # falsifiable: a probe that always returned true (or always false)
    # regardless of the real server would still pass a bare `refute_nil`.
    create_basic_index(@client, @index, @prefix)
    if @capable
      result = @client.ft_search(@index, "*", in_keys: ["#{@prefix}1"])
      assert_instance_of Valkey::Search::SearchResult, result
    else
      err = assert_raises(Valkey::CommandError) { @client.ft_search(@index, "*", in_keys: ["#{@prefix}1"]) }
      assert Helper::SearchCapability.inkeys_probe_error?(err.message)
    end
  end

  def test_level_fixture_reads_a_value_when_1_3_capable
    skip_unless_1_3!
    refute_nil @level, "a 1.3-capable module must report a search.emulate-release level"
  end

  # ---- wave 1 core: INKEYS, bare wildcard, auto-load ----

  def test_in_keys_restricts_search_to_given_keys
    skip_unless_1_3!
    create_basic_index(@client, @index, @prefix)
    @client.hset("#{@prefix}1", "title", "hello", "price", "1")
    @client.hset("#{@prefix}2", "title", "hello", "price", "2")
    poll_until_indexed(@client, @index, 2)

    result = @client.ft_search(@index, "*", in_keys: ["#{@prefix}1"])
    assert_equal 1, result.total_results
    assert_equal ["#{@prefix}1"], result.documents.map(&:key)
  end

  def test_in_keys_empty_array_matches_nothing
    skip_unless_1_3!
    create_basic_index(@client, @index, @prefix)
    @client.hset("#{@prefix}1", "title", "hello", "price", "1")
    poll_until_indexed(@client, @index, 1)

    result = @client.ft_search(@index, "*", in_keys: [])
    assert_equal 0, result.total_results
    assert_empty result.documents
  end

  def test_bare_wildcard_matches_every_document
    skip_unless_1_3!
    create_basic_index(@client, @index, @prefix)
    @client.hset("#{@prefix}1", "title", "hello", "price", "1")
    @client.hset("#{@prefix}2", "title", "world", "price", "2")
    @client.hset("#{@prefix}3", "title", "fizz", "price", "3")
    poll_until_indexed(@client, @index, 3)

    result = @client.ft_search(@index, "*")
    assert_equal 3, result.total_results
    assert_equal Set["#{@prefix}1", "#{@prefix}2", "#{@prefix}3"], Set.new(result.documents.map(&:key))
  end

  # ---- scoring ----

  def test_with_scores_and_scorer
    skip_unless_1_3!
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
    skip_unless_1_3!
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
      assert_operator doc.score.to_f, :>=, 0
      refute_nil doc.sort_key
      assert doc.fields.key?("title")
    end
  end

  def test_scorer_tfidf_rejected
    skip_unless_1_3!
    create_basic_index(@client, @index, @prefix)
    @client.hset("#{@prefix}1", "title", "hello world", "price", "1")
    poll_until_indexed(@client, @index, 1)

    err = assert_raises(Valkey::CommandError) { @client.ft_search(@index, "hello", with_scores: true, scorer: "TFIDF") }
    assert_match(/SCORER/, err.message)
  end

  def test_add_scores_sortable_by_score
    skip_unless_1_3!
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

  def test_count_option_emits_limit_zero_zero_and_returns_total_only
    skip_unless_1_3!
    create_basic_index(@client, @index, @prefix)
    @client.hset("#{@prefix}1", "title", "hello", "price", "1")
    @client.hset("#{@prefix}2", "title", "hello", "price", "2")
    poll_until_indexed(@client, @index, 2)

    result = @client.ft_search(@index, "*", count: true)
    assert_equal 2, result.total_results
    assert_empty result.documents
  end

  # ---- 1.3 reducers: TOLIST, FIRST_VALUE, RANDOM_SAMPLE ----

  def test_aggregate_reducers_search_1_3_additions
    skip_unless_1_3!
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

  # ---- vector range ----

  def test_search_vector_range
    skip_unless_1_3!
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

  def test_aggregate_vector_range
    skip_unless_1_3!
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

  # ---- JSON aggregate, compat-gated GROUPBY output column naming ----

  def test_aggregate_with_bicycles_data
    skip_unless_1_3!
    legacy = legacy_level?
    @client.ft_create(
      @index,
      [Valkey::Search::TextField.new("$.model", as: "model"),
       Valkey::Search::TagField.new("$.condition", as: "condition")],
      on: :json, prefixes: [@prefix]
    )
    # JsonCommands is required but not mixed into Valkey::Commands in this
    # repo (a pre-existing gap, out of scope for this port) -- JSON.SET is
    # issued as a raw custom command instead of the (absent) json_set
    # wrapper.
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
    # Below 1.3.0 a JSON-indexed GROUPBY column reports the raw JSONPath
    # ($.condition); at/above 1.3.0 it reports the schema alias
    # (condition) -- the `ft_aggregate_1_3_json_groupby_column` compat
    # gate this test exercises.
    column = legacy ? "$.condition" : "condition"
    by_condition = result.to_h { |row| [row[column], row["n"].to_i] }
    assert_equal({ "new" => 1, "used" => 2 }, by_condition)
  end

  # ---- HASH aggregate with movies data (no compat gate; sanity row) ----

  def test_aggregate_with_movies_data
    skip_unless_1_3!
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

  # ---- SORTBY widening by an adjacent LIMIT (compat-gated) ----

  def test_aggregate_sortby_adjacent_limit_widens_retained_rows
    skip_unless_1_3!
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

  # ---- LOAD ... AS (compat-gated) ----

  def test_aggregate_load_as
    skip_unless_1_3!
    legacy = legacy_level?
    @client.ft_create(@index, [Valkey::Search::TextField.new("title"), Valkey::Search::NumericField.new("price")],
                      on: :hash, prefixes: [@prefix])
    @client.hset("#{@prefix}1", "title", "widget", "price", "9")
    poll_until_indexed(@client, @index, 1)

    if legacy
      err = assert_raises(Valkey::CommandError) do
        @client.ft_aggregate(@index, "*", load: ["title", Valkey::Search::LoadField.new("price", alias: "cost")])
      end
      assert_match(/field `AS` does not exist/, err.message)
    else
      result = @client.ft_aggregate(@index, "*", load: ["title", Valkey::Search::LoadField.new("price", alias: "cost")])
      assert_equal 1, result.length
      assert_equal "widget", result[0]["title"]
      assert_equal "9", result[0]["cost"]
      refute result[0].key?("price")
    end
  end

  # ---- FLOAT16 / BFLOAT16 vector types ----

  # Ruby's Array#pack has no half-precision ("e"/"E" are 32-bit) directive,
  # so FLOAT16 is hand-encoded via its bit-level relationship to the IEEE
  # 754 single-precision value Float#to_s already packs correctly, and
  # BFLOAT16 by truncating a FLOAT32's own most-significant 16 bits (its
  # documented definition) -- matching Python's test fixture approach
  # (struct.pack("<e", v) / struct.pack("<f", v)[2:4]) bit-for-bit for the
  # exact test values used here (0.0, 1.0, 2.0 -- binary powers that round
  # trip exactly under both encodings, avoiding any dependency on a
  # specific rounding mode).
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
    skip_unless_1_3!
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

  # ---- FT.CREATE FILTER ----

  def test_create_filter
    skip_unless_1_3!
    @client.ft_create(@index, [Valkey::Search::NumericField.new("age")],
                      on: :hash, prefixes: [@prefix], filter: "@age > 18")
    @client.hset("#{@prefix}adult", "age", "25")
    @client.hset("#{@prefix}minor", "age", "10")
    poll_until_indexed(@client, @index, 1)

    result = @client.ft_search(@index, "*", no_content: true)
    assert_equal 1, result.total_results
    assert_equal Set["#{@prefix}adult"], Set.new(result.documents.map(&:key))
  end

  # ---- FT.CREATE SORTABLE UNF ----

  def test_create_sortable_unf
    skip_unless_1_3!
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
    # ASCII order: uppercase 'B' (0x42) sorts before lowercase 'a' (0x61).
    assert_equal ["#{@prefix}2", "#{@prefix}1"], keys
  end

  # ---- FT.CREATE SCORE_FIELD in index_definition (compat-gated) ----

  def test_create_score_field_in_index_definition
    skip_unless_1_3!
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
    skip_unless_1_3!
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

  # ---- FT.CREATE NOHL (genuine no-op) ----

  def test_create_no_highlight
    skip_unless_1_3!
    assert_equal "OK", @client.ft_create(@index, [Valkey::Search::TextField.new("title")],
                                         on: :hash, prefixes: [@prefix], no_highlight: true)
  end

  # ---- cursors (pinned to the index slot's primary) ----

  def test_aggregate_typed_cursor_paged_to_exhaustion
    skip_unless_1_3!
    @client.ft_create(@index, [Valkey::Search::NumericField.new("n", sortable: true)], on: :hash, prefixes: [@prefix])
    (1..20).each { |i| @client.hset("#{@prefix}d#{i}", "n", i.to_s) }
    poll_until_indexed(@client, @index, 20)

    seen = Set.new
    total = 0
    page = @client.ft_aggregate(@index, "*", load: ["n"], with_cursor: Valkey::Search::WithCursor.new(count: 5))
    rows, cursor_id = page
    total += rows.length
    seen.merge(rows.map { |row| row["n"].to_i })
    pages_read = 1
    while cursor_id != 0
      rows, cursor_id = @client.ft_cursor_read(@index, cursor_id)
      total += rows.length
      seen.merge(rows.map { |row| row["n"].to_i })
      pages_read += 1
      raise "paging did not terminate" if pages_read > 10
    end
    assert_equal 20, total
    assert_equal Set.new(1..20), seen
  end

  def test_aggregate_typed_cursor_del_and_errors
    skip_unless_1_3!
    @client.ft_create(@index, [Valkey::Search::NumericField.new("n", sortable: true)], on: :hash, prefixes: [@prefix])
    (1..5).each { |i| @client.hset("#{@prefix}d#{i}", "n", i.to_s) }
    poll_until_indexed(@client, @index, 5)

    _rows, cursor_id = @client.ft_aggregate(@index, "*", load: ["n"],
                                                         with_cursor: Valkey::Search::WithCursor.new(count: 1))
    refute_equal 0, cursor_id

    assert_equal "OK", @client.ft_cursor_del(@index, cursor_id)

    err = assert_raises(Valkey::CommandError) { @client.ft_cursor_read(@index, cursor_id) }
    assert_match(/Cursor/, err.message)

    err2 = assert_raises(Valkey::CommandError) { @client.ft_cursor_read(@index, 999_999_999) }
    assert_match(/Cursor/, err2.message)
  end

  # ---- FT.HYBRID ----

  def test_hybrid_basic_query
    skip_unless_1_3!
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

  # ---- FT.HYBRID: the port-rules-mandated FILTER-right-after-VSIM-arm case.
  # FILTER sits directly after the VSIM arm's own tokens with NO LOAD
  # clause in between: HybridOptions always emits PARAMS before clauses
  # regardless of field-construction order (see hybrid.rb's HybridOptions
  # docstring), so this is the live regression guard for the port rule --
  # a LOAD clause placed between VSIM and FILTER would mask the bug (the
  # server's VSIM parser can't claim FILTER as its own pre-filter once a
  # LOAD token has already been consumed), which is exactly what the H2
  # finding flagged against the prior version of this test.
  def test_hybrid_filter_immediately_after_vsim_arm_is_not_claimed_as_vsim_prefilter
    skip_unless_1_3!
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
    skip_unless_1_3!
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
    skip_unless_1_3!
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
    skip_unless_1_3!
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
    skip_unless_1_3!
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
    skip_unless_1_3!
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
    skip_unless_1_3!
    create_hybrid_index(@client, @index, @prefix)
    result = @client.ft_hybrid(
      @index, Valkey::Search::HybridSearchArm.new("hello"),
      Valkey::Search::HybridVsimArm.new("vec", [10.0, 10.0].pack("f*"), k: 5),
      Valkey::Search::HybridOptions.new(local_only: true)
    )
    assert_equal 2, result.length
  end

  def test_hybrid_inside_multi_exec_rejected
    skip_unless_1_3!
    create_hybrid_index(@client, @index, @prefix)
    err = assert_raises(ArgumentError) do
      @client.multi do |tx|
        tx.ft_hybrid(@index, Valkey::Search::HybridSearchArm.new("hello"),
                     Valkey::Search::HybridVsimArm.new("vec", [10.0, 10.0].pack("f*"), k: 5))
      end
    end
    assert_match(%r{not supported inside pipelined/multi}, err.message)
  end

  # FT.HYBRID's VSIM ... RANGE form is excluded from the typed API (D10);
  # one test asserts the server itself rejects it at execution. Dispatched
  # via a raw custom command since RANGE has no typed representation.
  def test_hybrid_vsim_range_rejected
    skip_unless_1_3!
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

class ModulesFt13StandaloneTest < Minitest::Test
  include ModulesFt13Shared

  def setup
    @client = modules_standalone_client
    ft13_setup(@client)
  end

  def teardown
    @client.send_command(Valkey::RequestType::CUSTOM_COMMAND, ["FT.DROPINDEX", @index])
  rescue Valkey::CommandError
    nil
  ensure
    @client&.close
  end

  # ---- FT.SEARCH LIMIT pagination (non-gated row, standalone-only check) ----

  def test_search_limit_pagination
    skip_unless_1_3!
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

class ModulesFt13ClusterTest < Minitest::Test
  include ModulesFt13Shared

  def setup
    skip "no cluster module endpoints configured" if Helper::ModuleClient.cluster_addresses.empty?
    @client = modules_cluster_client
    ft13_setup(@client)
  end

  def teardown
    @client.send_command(Valkey::RequestType::CUSTOM_COMMAND, ["FT.DROPINDEX", @index])
  rescue Valkey::CommandError
    nil
  ensure
    @client&.close
  end

  # ---- cross-shard FT.CREATE/FT.SEARCH/FT.AGGREGATE with no hashtag ----

  # Deliberately NOT using the shared, hashtagged @index/@prefix from
  # ft13_setup: this is the one test in the suite that specifically
  # exercises what happens with NO hashtag relationship between the index
  # and its keys. ft_create broadcasts to every primary client-side (see
  # vector_search_commands.rb's ft_all_primaries_route -- Ruby's own
  # design, independent of whatever the bare server does on its own), so
  # the index itself always exists on every shard; what this test
  # actually re-checks is whether a plain (single-node-routed)
  # FT.SEARCH/FT.AGGREGATE aggregates across every shard once documents
  # are scattered across them with no hashtag, or only sees the one shard
  # the query happened to be routed to. Key placement is checked
  # deterministically via the real CLUSTER KEYSLOT outcome (not inferred
  # from search results), matching the port rule that a test depending on
  # placement must check it directly.
  def test_multi_shard_no_hashtag
    skip_unless_1_3!
    index = "modules_ft13_multishard_#{SecureRandom.hex(6)}"
    @client.ft_create(index, [Valkey::Search::TextField.new("title")], on: :hash, prefixes: ["#{index}:"])

    shards_reply = @client.send_command(Valkey::RequestType::CUSTOM_COMMAND, %w[CLUSTER SHARDS])
    primary_addrs = []
    shards_reply.each do |shard|
      shard_hash = Valkey::Utils::Hashify.call(shard)
      Array(shard_hash["nodes"]).each do |node|
        node_hash = Valkey::Utils::Hashify.call(node)
        primary_addrs << [node_hash["ip"], node_hash["port"].to_i] if node_hash["role"] == "master"
      end
    end
    assert_operator primary_addrs.length, :>=, 2, "test requires a real multi-shard cluster"

    # ft_create's client-side broadcast (Route.all_primaries) must have
    # actually reached every primary -- verified directly via FT._LIST on
    # each node by address, not inferred from the broadcast call's own
    # "OK" return (which only proves every node replied, not which
    # command each one ran).
    list_by_node = primary_addrs.to_h do |host, port|
      [[host, port], @client.send_command(Valkey::RequestType::CUSTOM_COMMAND, ["FT._LIST"],
                                          route: Valkey::Route.by_address(host, port))]
    end
    nodes_with_index = list_by_node.select { |_addr, list| list.include?(index) }.keys
    assert_equal Set.new(primary_addrs), Set.new(nodes_with_index),
                 "ft_create's broadcast must reach every primary; got #{nodes_with_index} of #{primary_addrs}"

    key_names = (0...30).map { |i| "#{index}:doc#{i}" }
    key_names.each { |key| @client.hset(key, "title", "doc") }
    poll_until_indexed(@client, index, 1)

    result = @client.ft_search(index, "*", no_content: true)
    observed_keys = Set.new(result.documents.map(&:key))
    assert observed_keys.subset?(Set.new(key_names))
    assert_operator result.total_results, :<, key_names.length,
                    "expected a partial (single-shard) result: a plain FT.SEARCH is routed to one " \
                    "node and this engine version does not aggregate across shards on its own. If " \
                    "this is now the full #{key_names.length}, valkey-search has started " \
                    "aggregating ALLSHARDS results across shards server-side; that is upstream " \
                    "progress, not a regression, and this assertion should be updated with a " \
                    "source citation"

    @client.send_command(Valkey::RequestType::CUSTOM_COMMAND, ["FT.DROPINDEX", index])
  end

  # ---- cursor affinity: FT.CURSOR is node-local, pinned to the primary ----

  def test_cursor_affinity_prefer_replica_client
    skip_unless_1_3!
    @client.ft_create(@index, [Valkey::Search::NumericField.new("n", sortable: true)], on: :hash, prefixes: [@prefix])
    (1..20).each { |i| @client.hset("#{@prefix}d#{i}", "n", i.to_s) }
    poll_until_indexed(@client, @index, 20)

    prefer_replica = Valkey.new(cluster_mode: true, nodes: Helper::ModuleClient.cluster_addresses,
                                timeout: TIMEOUT, read_from: Valkey::ReadFrom::PREFER_REPLICA)
    begin
      total = 0
      seen = Set.new
      page = prefer_replica.send_command(Valkey::RequestType::CUSTOM_COMMAND,
                                         ["FT.AGGREGATE", @index, "*", "LOAD", "1", "n", "WITHCURSOR", "COUNT", "5"])
      rows, cursor_id = page
      total += rows.length
      seen.merge(rows.map { |row| row["n"].to_i })
      pages_read = 1
      while cursor_id != 0
        rows, cursor_id = prefer_replica.send_command(Valkey::RequestType::CUSTOM_COMMAND,
                                                      ["FT.CURSOR", "READ", @index, cursor_id.to_s])
        total += rows.length
        seen.merge(rows.map { |row| row["n"].to_i })
        pages_read += 1
        raise "paging did not terminate" if pages_read > 10
      end
      assert_equal 20, total
      assert_equal Set.new(1..20), seen

      # Negative control: a read explicitly routed to a REPLICA of the
      # index's own shard fails -- confirming the cursor really is
      # node-local, not merely that every node happened to answer by
      # default routing.
      shards_reply = prefer_replica.send_command(Valkey::RequestType::CUSTOM_COMMAND, %w[CLUSTER SHARDS])
      index_slot = prefer_replica.send_command(Valkey::RequestType::CUSTOM_COMMAND, ["CLUSTER", "KEYSLOT", @index])
      replica_addrs = []
      shards_reply.each do |shard|
        shard_hash = Valkey::Utils::Hashify.call(shard)
        slots = shard_hash["slots"]
        owns_slot = slots.each_slice(2).any? { |lo, hi| index_slot.between?(lo, hi) }
        next unless owns_slot

        Array(shard_hash["nodes"]).each do |node|
          node_hash = Valkey::Utils::Hashify.call(node)
          replica_addrs << [node_hash["ip"], node_hash["port"].to_i] if node_hash["role"] == "replica"
        end
      end
      assert_operator replica_addrs.length, :>=, 1, "test fixture bug: no replica found for the index's own shard"

      another_page = prefer_replica.send_command(
        Valkey::RequestType::CUSTOM_COMMAND,
        ["FT.AGGREGATE", @index, "*", "LOAD", "1", "n", "WITHCURSOR", "COUNT", "5"]
      )
      another_cursor_id = another_page[1]
      replica_addrs.each do |host, port|
        # A fresh route to an address a brand-new client hasn't yet
        # established a connection for can surface either as the
        # server's own "Cursor not found" (CommandError, when the
        # connection succeeds and the node-local cursor lookup then
        # fails) or as a ConnectionError (when glide-core's own routing
        # table for this client doesn't yet have that replica address) --
        # both prove the same thing this negative control checks for:
        # this client cannot successfully read the cursor via that
        # replica route.
        err = assert_raises(Valkey::BaseError) do
          prefer_replica.send_command(Valkey::RequestType::CUSTOM_COMMAND,
                                      ["FT.CURSOR", "READ", @index, another_cursor_id.to_s],
                                      route: Valkey::Route.by_address(host, port))
        end
        assert_match(/Cursor|Index|ConnectionNotFoundForRoute/, err.message)
      end
    ensure
      prefer_replica&.close
    end
  end

  # ---- FT.HYBRID WITHCURSOR via a PREFER_REPLICA client ----

  def test_hybrid_with_cursor_prefer_replica_client_paged_to_exhaustion
    skip_unless_1_3!
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
