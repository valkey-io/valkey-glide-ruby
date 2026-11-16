# frozen_string_literal: true

# Load only the pieces this unit test needs — see search_builder_test.rb's
# header comment for why (pure Ruby serialization, no native FFI).
$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require "minitest/autorun"
require "valkey/request_type"
require "valkey/search"
require "valkey/route"
require "valkey/commands/vector_search_commands"

# Unit tests for the valkey-search 1.3 additions: FT.HYBRID's builder
# classes, WITHCURSOR, and the FT.HYBRID argv assembly in
# VectorSearchCommands#ft_hybrid. Pure Ruby — no server, no FFI.
#
# The three argv-assembly tests below (HybridArgvParity) are checked
# byte-for-byte against Python's #7335 test_options.py fixtures (the same
# upstream commit this port's CHANGELOG cites), satisfying the port
# acceptance criterion that FT.HYBRID argv must match Python's.
class SearchHybridTest < Minitest::Test
  def test_search_arm_basic
    args = Valkey::Search::HybridSearchArm.new("hello world").to_args
    assert_equal ["SEARCH", "hello world"], args
  end

  def test_search_arm_scorer_and_yield_score_as
    args = Valkey::Search::HybridSearchArm.new("hello world", scorer: "BM25STD", yield_score_as: "ss").to_args
    assert_equal ["SEARCH", "hello world", "SCORER", "BM25STD", "YIELD_SCORE_AS", "ss"], args
  end

  def test_vsim_arm_param_reference_no_knn
    arm = Valkey::Search::HybridVsimArm.new("vec", "$myvec")
    assert arm.param_reference?
    assert_equal ["VSIM", "@vec", "$myvec"], arm.to_args
  end

  def test_vsim_arm_raw_bytes_requires_generated_name
    arm = Valkey::Search::HybridVsimArm.new("vec", "rawbytes")
    refute arm.param_reference?
    assert_raises(ArgumentError) { arm.to_args }
    assert_equal ["VSIM", "@vec", "$gen123"], arm.to_args(generated_param_name: "$gen123")
  end

  # H3: param reference must be decided by Ruby type/encoding, never by the
  # vector's leading byte. Binary-encoded bytes whose first byte happens to
  # be 0x24 ("$") must still be treated as raw vector data requiring a
  # generated PARAMS entry, not misread as a parameter reference.
  def test_vsim_arm_binary_bytes_starting_with_dollar_sign_are_not_a_reference
    raw_vector = [1.0000043, 0.2].pack("e*").b
    assert_equal "$".b, raw_vector.byteslice(0, 1), "fixture must actually start with the $ byte (0x24)"
    arm = Valkey::Search::HybridVsimArm.new("vec", raw_vector)
    refute arm.param_reference?, "binary-encoded bytes starting with 0x24 must not be treated as a $ reference"
    assert_raises(ArgumentError) { arm.to_args }
    args = arm.to_args(generated_param_name: "$gen456")
    assert_equal ["VSIM", "@vec", "$gen456"], args
  end

  # A non-binary String starting with "$" is still a reference, regardless
  # of its encoding being the Ruby default (UTF-8) rather than explicitly
  # binary -- the type/encoding check, not the byte value, is what matters.
  def test_vsim_arm_utf8_dollar_string_is_a_reference
    arm = Valkey::Search::HybridVsimArm.new("vec", "$named_param")
    assert arm.param_reference?
    assert_equal ["VSIM", "@vec", "$named_param"], arm.to_args
  end

  def test_vsim_arm_knn_block
    arm = Valkey::Search::HybridVsimArm.new("vec", "$v", k: 10, ef_runtime: 50, shard_k_ratio: 0.5)
    assert_equal ["VSIM", "@vec", "$v", "KNN", 6, "K", 10, "EF_RUNTIME", 50, "SHARD_K_RATIO", 0.5], arm.to_args
  end

  def test_vsim_arm_ef_runtime_with_adhoc_policy_raises
    filter = Valkey::Search::HybridVsimFilter.new("@x:1", policy: Valkey::Search::HybridFilterPolicy::ADHOC)
    assert_raises(ArgumentError) do
      Valkey::Search::HybridVsimArm.new("vec", "$v", ef_runtime: 50, filter: filter)
    end
  end

  def test_vsim_filter_uncounted_form
    assert_equal ["FILTER", "@title:hello"], Valkey::Search::HybridVsimFilter.new("@title:hello").to_args
  end

  def test_vsim_filter_counted_form_with_policy
    filter = Valkey::Search::HybridVsimFilter.new(
      "@title:hello", policy: Valkey::Search::HybridFilterPolicy::BATCHES, batch_size: 50
    )
    assert_equal ["FILTER", 5, "@title:hello", "POLICY", "BATCHES", "BATCH_SIZE", 50], filter.to_args
  end

  def test_vsim_filter_batch_size_without_batches_policy_raises
    assert_raises(ArgumentError) { Valkey::Search::HybridVsimFilter.new("@x:1", batch_size: 50) }
  end

  def test_combine_rrf
    args = Valkey::Search::HybridCombine.rrf(constant: 60, window: 20, yield_score_as: "s").to_args
    assert_equal ["COMBINE", "RRF", 6, "CONSTANT", 60, "WINDOW", 20, "YIELD_SCORE_AS", "s"], args
  end

  def test_combine_rrf_negative_constant_raises
    assert_raises(ArgumentError) { Valkey::Search::HybridCombine.rrf(constant: -1) }
  end

  def test_combine_linear
    args = Valkey::Search::HybridCombine.linear(alpha: 0.3, beta: 0.7).to_args
    assert_equal ["COMBINE", "LINEAR", 4, "ALPHA", 0.3, "BETA", 0.7], args
  end

  def test_combine_linear_one_without_other_raises
    assert_raises(ArgumentError) { Valkey::Search::HybridCombine.linear(alpha: 0.3) }
  end

  def test_combine_function
    args = Valkey::Search::HybridCombine.function("@ss + @vs", window: 100).to_args
    assert_equal ["COMBINE", "FUNCTION", 4, "EXPR", "@ss + @vs", "WINDOW", 100], args
  end

  def test_with_cursor
    assert_equal ["WITHCURSOR", "COUNT", 5], Valkey::Search::WithCursor.new(count: 5).to_args
  end

  def test_load_field_with_alias
    assert_equal %w[price AS p], Valkey::Search::LoadField.new("price", alias: "p").to_args
  end

  def test_load_field_without_alias
    assert_equal ["price"], Valkey::Search::LoadField.new("price").to_args
  end
end

# Mirrors Python's TestFtHybridOptions in test_options.py (#7335) exactly,
# including names, to pin the same ordering guarantees:
# LOCALONLY -> LOAD -> TIMEOUT -> PARAMS -> clauses -> WITHCURSOR -> DIALECT.
class HybridOptionsTest < Minitest::Test
  def test_empty_options_emits_nothing
    assert_equal [], Valkey::Search::HybridOptions.new.to_args
  end

  def test_load_all
    assert_equal %w[LOAD *], Valkey::Search::HybridOptions.new(load_all: true).to_args
  end

  def test_load_fields
    args = Valkey::Search::HybridOptions.new(load_fields: %w[title price]).to_args
    assert_equal ["LOAD", 2, "title", "price"], args
  end

  def test_local_only_emitted_first_regardless_of_field_order
    args = Valkey::Search::HybridOptions.new(local_only: true, load_fields: ["title"], dialect: 2).to_args
    assert_equal ["LOCALONLY", "LOAD", 1, "title", "DIALECT", 2], args
  end

  def test_params
    args = Valkey::Search::HybridOptions.new(params: { "q" => "value" }).to_args
    assert_equal ["PARAMS", 2, "q", "value"], args
  end

  def test_generated_vsim_param_merged_with_caller_params
    args = Valkey::Search::HybridOptions.new(params: { "other" => "x" })
                                        .to_args(generated_vsim_param: { "generated123" => "rawbytes" })
    assert_equal "PARAMS", args[0]
    assert_equal 4, args[1]
    pairs = args[2..].each_slice(2).to_h { |k, v| [k, v] }
    assert_equal({ "other" => "x", "generated123" => "rawbytes" }, pairs)
  end

  def test_generated_vsim_param_name_collision_raises
    opts = Valkey::Search::HybridOptions.new(params: { "q" => "caller value" })
    assert_raises(ArgumentError) { opts.to_args(generated_vsim_param: { "q" => "generated value" }) }
  end

  def test_timeout
    assert_equal ["TIMEOUT", 100], Valkey::Search::HybridOptions.new(timeout: 100).to_args
  end

  def test_clauses_applied_in_order
    args = Valkey::Search::HybridOptions.new(clauses: [Valkey::Search::Limit.new(0, 10)]).to_args
    assert_equal ["LIMIT", 0, 10], args
  end

  # Byte-identical to Python's test_params_emitted_before_clauses. This is
  # the port-rules-mandated regression case: a FILTER clause right after the
  # VSIM arm (no LOAD in between) would otherwise be claimed by the server's
  # VSIM parser as a pre-filter instead of an aggregate-pipeline FILTER.
  def test_params_emitted_before_clauses
    args = Valkey::Search::HybridOptions.new(
      clauses: [Valkey::Search::Filter.new("@price>0")], params: { "q" => "value" }
    ).to_args
    assert_equal ["PARAMS", 2, "q", "value", "FILTER", "@price>0"], args
  end

  def test_local_only_params_and_clauses_order
    args = Valkey::Search::HybridOptions.new(
      local_only: true,
      load_fields: ["title"],
      params: { "q" => "value" },
      clauses: [Valkey::Search::Limit.new(0, 10)]
    ).to_args
    assert_equal ["LOCALONLY", "LOAD", 1, "title", "PARAMS", 2, "q", "value", "LIMIT", 0, 10], args
  end
end

# The 3 FT.HYBRID argv cases required to be byte-identical to Python,
# exercised through VectorSearchCommands#ft_hybrid's full command assembly
# (not just HybridOptions#to_args in isolation), against a fake client.
class HybridArgvParityTest < Minitest::Test
  class FakeClient
    include Valkey::Commands::VectorSearchCommands

    attr_reader :captured

    def initialize(cluster_mode: false)
      @cluster_mode = cluster_mode
    end

    def send_command(_command_type, command_args = [], route: nil)
      @captured = command_args
      @route = route
      ["OK"]
    end
  end

  # Case 1: basic two-arm call with a param-reference vector (no COMBINE, no
  # LOAD, no cursor) — Python's `ft.hybrid(client, "idx", FtHybridSearchArm("hello world"),
  # FtHybridVsimArm("vec", "$myvec", k=10))`.
  def test_case_basic_param_reference
    client = FakeClient.new
    client.ft_hybrid(
      "idx",
      Valkey::Search::HybridSearchArm.new("hello world"),
      Valkey::Search::HybridVsimArm.new("vec", "$myvec", k: 10)
    )
    assert_equal(
      ["FT.HYBRID", "idx", "SEARCH", "hello world", "VSIM", "@vec", "$myvec", "KNN", 2, "K", 10],
      client.captured
    )
  end

  # Case 2: RRF combine + LOAD + WITHCURSOR, matching #7335's own docstring
  # example verbatim (modulo the uuid4-generated PARAMS name, which this
  # case avoids by using an explicit $-reference vector so the argv is
  # fully deterministic for a byte-identical comparison).
  def test_case_combine_load_with_cursor
    client = FakeClient.new
    client.ft_hybrid(
      "idx",
      Valkey::Search::HybridSearchArm.new("hello world", yield_score_as: "ss"),
      Valkey::Search::HybridVsimArm.new("vec", "$qv", k: 10, yield_score_as: "vs"),
      Valkey::Search::HybridOptions.new(
        combine: Valkey::Search::HybridCombine.rrf(constant: 60),
        load_fields: ["title"],
        with_cursor: Valkey::Search::WithCursor.new(count: 10)
      )
    )
    assert_equal(
      [
        "FT.HYBRID", "idx",
        "SEARCH", "hello world", "YIELD_SCORE_AS", "ss",
        "VSIM", "@vec", "$qv", "KNN", 2, "K", 10, "YIELD_SCORE_AS", "vs",
        "COMBINE", "RRF", 2, "CONSTANT", 60,
        "LOAD", 1, "title",
        "WITHCURSOR", "COUNT", 10
      ],
      client.captured
    )
  end

  # Case 3: the port-rules-mandated FILTER-right-after-VSIM-arm regression
  # case, through the full ft_hybrid call path (no LOAD, no combine) — this
  # is the exact scenario jamesx's #7335 review finding targets: without
  # emitting PARAMS before the FILTER clause, the server's VSIM parser
  # would claim the FILTER as its own pre-filter instead.
  def test_case_post_vsim_filter_no_load_no_combine
    client = FakeClient.new
    client.ft_hybrid(
      "idx",
      Valkey::Search::HybridSearchArm.new("hello world"),
      Valkey::Search::HybridVsimArm.new("vec", "$myvec", k: 10),
      Valkey::Search::HybridOptions.new(
        clauses: [Valkey::Search::Filter.new("@price>0")],
        params: { "extra" => "value" }
      )
    )
    assert_equal(
      [
        "FT.HYBRID", "idx",
        "SEARCH", "hello world",
        "VSIM", "@vec", "$myvec", "KNN", 2, "K", 10,
        "PARAMS", 2, "extra", "value",
        "FILTER", "@price>0"
      ],
      client.captured
    )
  end

  def test_raw_vector_bytes_generates_params_entry
    client = FakeClient.new
    client.ft_hybrid(
      "idx",
      Valkey::Search::HybridSearchArm.new("q"),
      Valkey::Search::HybridVsimArm.new("vec", "rawbytes", k: 5)
    )
    args = client.captured
    assert_equal "FT.HYBRID", args[0]
    params_idx = args.index("PARAMS")
    refute_nil params_idx, "expected a generated PARAMS entry for raw vector bytes"
    assert_equal 2, args[params_idx + 1]
    generated_name = args[params_idx + 2]
    assert_equal "rawbytes", args[params_idx + 3]
    vsim_idx = args.index("VSIM")
    assert_equal "$#{generated_name}", args[vsim_idx + 2]
  end

  def test_with_cursor_routes_to_index_slot_primary_in_cluster_mode
    client = FakeClient.new(cluster_mode: true)
    client.ft_hybrid(
      "idx",
      Valkey::Search::HybridSearchArm.new("q"),
      Valkey::Search::HybridVsimArm.new("vec", "$v", k: 5),
      Valkey::Search::HybridOptions.new(with_cursor: Valkey::Search::WithCursor.new(count: 1))
    )
    assert_equal :slot_key, client.instance_variable_get(:@route).instance_variable_get(:@route_type)
    assert_equal "idx", client.instance_variable_get(:@route).instance_variable_get(:@slot_key)
  end

  def test_without_cursor_does_not_route_in_cluster_mode
    client = FakeClient.new(cluster_mode: true)
    client.ft_hybrid("idx", Valkey::Search::HybridSearchArm.new("q"),
                     Valkey::Search::HybridVsimArm.new("vec", "$v", k: 5))
    assert_nil client.instance_variable_get(:@route)
  end
end

# FT.CURSOR READ/DEL argv and routing.
class CursorCommandsTest < Minitest::Test
  class FakeClient
    include Valkey::Commands::VectorSearchCommands

    attr_reader :captured, :route

    def initialize(cluster_mode: false)
      @cluster_mode = cluster_mode
    end

    def send_command(_command_type, command_args = [], route: nil)
      @captured = command_args
      @route = route
      ["OK"]
    end
  end

  def test_cursor_read_basic
    client = FakeClient.new
    client.ft_cursor_read("idx", 14_058_138_254)
    assert_equal ["FT.CURSOR", "READ", "idx", "14058138254"], client.captured
  end

  def test_cursor_read_with_count
    client = FakeClient.new
    client.ft_cursor_read("idx", 42, count: 5)
    assert_equal ["FT.CURSOR", "READ", "idx", "42", "COUNT", 5], client.captured
  end

  def test_cursor_del
    client = FakeClient.new
    client.ft_cursor_del("idx", 42)
    assert_equal ["FT.CURSOR", "DEL", "idx", "42"], client.captured
  end

  def test_cursor_read_routes_to_index_slot_primary_in_cluster_mode
    client = FakeClient.new(cluster_mode: true)
    client.ft_cursor_read("idx", 42)
    assert_equal :slot_key, client.route.instance_variable_get(:@route_type)
    assert_equal "idx", client.route.instance_variable_get(:@slot_key)
    assert_equal :primary, client.route.instance_variable_get(:@slot_type)
  end

  def test_cursor_read_no_route_in_standalone
    client = FakeClient.new(cluster_mode: false)
    client.ft_cursor_read("idx", 42)
    assert_nil client.route
  end
end
