# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require "minitest/autorun"
require "valkey/request_type"
require "valkey/search"
require "valkey/route"
require "valkey/commands/vector_search_commands"

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

  def test_vsim_arm_binary_bytes_starting_with_dollar_sign_are_not_a_reference
    raw_vector = [1.0000043, 0.2].pack("e*").b
    assert_equal "$".b, raw_vector.byteslice(0, 1), "fixture must actually start with the $ byte (0x24)"
    arm = Valkey::Search::HybridVsimArm.new("vec", raw_vector)
    refute arm.param_reference?, "binary-encoded bytes starting with 0x24 must not be treated as a $ reference"
    assert_raises(ArgumentError) { arm.to_args }
    args = arm.to_args(generated_param_name: "$gen456")
    assert_equal ["VSIM", "@vec", "$gen456"], args
  end

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

  def test_vsim_filter_integer_expression_uses_counted_form
    assert_equal ["FILTER", 1, "2024"], Valkey::Search::HybridVsimFilter.new("2024").to_args
    assert_equal ["FILTER", 1, "1"], Valkey::Search::HybridVsimFilter.new("1").to_args
    assert_equal ["FILTER", 1, "-5"], Valkey::Search::HybridVsimFilter.new("-5").to_args
  end

  def test_vsim_filter_integer_expression_with_policy_stays_counted
    filter = Valkey::Search::HybridVsimFilter.new("2024", policy: Valkey::Search::HybridFilterPolicy::ADHOC)
    assert_equal ["FILTER", 3, "2024", "POLICY", "ADHOC"], filter.to_args
  end

  def test_vsim_filter_non_integer_expression_stays_uncounted
    assert_equal ["FILTER", "@year:[2024 2024]"], Valkey::Search::HybridVsimFilter.new("@year:[2024 2024]").to_args
    assert_equal ["FILTER", "1.5"], Valkey::Search::HybridVsimFilter.new("1.5").to_args
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
    assert_equal %w[price AS p], Valkey::Search::LoadField.new("price", as: "p").to_args
  end

  def test_load_field_without_alias
    assert_equal ["price"], Valkey::Search::LoadField.new("price").to_args
  end
end

class HybridOptionsTest < Minitest::Test
  def test_empty_options_emits_nothing
    assert_equal [], Valkey::Search::HybridOptions.new.to_args
  end

  def test_load_all_symbol
    assert_equal %w[LOAD *], Valkey::Search::HybridOptions.new(load: :all).to_args
  end

  def test_load_all_star
    assert_equal %w[LOAD *], Valkey::Search::HybridOptions.new(load: "*").to_args
  end

  def test_load_fields
    args = Valkey::Search::HybridOptions.new(load: %w[title price]).to_args
    assert_equal ["LOAD", 2, "title", "price"], args
  end

  def test_load_rejects_unsupported_type
    assert_raises(ArgumentError) { Valkey::Search::HybridOptions.new(load: 1).to_args }
  end

  def test_local_only_emitted_first_regardless_of_field_order
    args = Valkey::Search::HybridOptions.new(local_only: true, load: ["title"], dialect: 2).to_args
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

  def test_params_emitted_before_clauses
    args = Valkey::Search::HybridOptions.new(
      clauses: [Valkey::Search::Filter.new("@price>0")], params: { "q" => "value" }
    ).to_args
    assert_equal ["PARAMS", 2, "q", "value", "FILTER", "@price>0"], args
  end

  def test_local_only_params_and_clauses_order
    args = Valkey::Search::HybridOptions.new(
      local_only: true,
      load: ["title"],
      params: { "q" => "value" },
      clauses: [Valkey::Search::Limit.new(0, 10)]
    ).to_args
    assert_equal ["LOCALONLY", "LOAD", 1, "title", "PARAMS", 2, "q", "value", "LIMIT", 0, 10], args
  end
end

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

  def test_case_combine_load_with_cursor
    client = FakeClient.new
    client.ft_hybrid(
      "idx",
      Valkey::Search::HybridSearchArm.new("hello world", yield_score_as: "ss"),
      Valkey::Search::HybridVsimArm.new("vec", "$qv", k: 10, yield_score_as: "vs"),
      Valkey::Search::HybridOptions.new(
        combine: Valkey::Search::HybridCombine.rrf(constant: 60),
        load: ["title"],
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

  def test_with_cursor_sends_no_client_side_route
    client = FakeClient.new(cluster_mode: true)
    client.ft_hybrid(
      "idx",
      Valkey::Search::HybridSearchArm.new("q"),
      Valkey::Search::HybridVsimArm.new("vec", "$v", k: 5),
      Valkey::Search::HybridOptions.new(with_cursor: Valkey::Search::WithCursor.new(count: 1))
    )
    assert_nil client.instance_variable_get(:@route), "cursor routing is owned by glide-core"
  end

  def search_arm = Valkey::Search::HybridSearchArm.new("q")
  def vsim_arm = Valkey::Search::HybridVsimArm.new("vec", "$v", k: 5)

  def test_rejected_in_batch_names_ft_hybrid
    client = FakeClient.new
    client.instance_variable_set(:@commands, [])
    client.instance_variable_set(:@futures, [])
    err = assert_raises(ArgumentError) { client.ft_hybrid("idx", search_arm, vsim_arm) }
    assert_match(%r{not supported inside pipelined/multi; use Valkey#call to issue FT\.HYBRID and handle the raw reply},
                 err.message)
    refute_match(/FT\.AGGREGATE/, err.message)
  end

  def test_rejected_in_multi
    client = FakeClient.new
    client.instance_variable_set(:@in_multi, true)
    assert_raises(ArgumentError) { client.ft_hybrid("idx", search_arm, vsim_arm) }
  end

  def test_hash_options_raise_argument_error
    err = assert_raises(ArgumentError) { FakeClient.new.ft_hybrid("idx", search_arm, vsim_arm, { with_cursor: 1 }) }
    assert_match(/options must be a Valkey::Search::HybridOptions, got Hash/, err.message)
  end

  def test_keyword_options_match_options_object
    via_object = FakeClient.new
    via_object.ft_hybrid("idx", search_arm, vsim_arm, Valkey::Search::HybridOptions.new(load: ["title"], timeout: 100))
    via_keywords = FakeClient.new
    via_keywords.ft_hybrid("idx", search_arm, vsim_arm, load: ["title"], timeout: 100)
    assert_equal via_object.captured, via_keywords.captured
  end

  def test_keyword_options_apply_combine
    client = FakeClient.new
    client.ft_hybrid("idx", search_arm, vsim_arm, combine: Valkey::Search::HybridCombine.rrf(constant: 60))
    assert_includes client.captured, "RRF"
  end

  def test_options_object_and_keywords_together_raise_argument_error
    err = assert_raises(ArgumentError) do
      FakeClient.new.ft_hybrid("idx", search_arm, vsim_arm, Valkey::Search::HybridOptions.new, timeout: 100)
    end
    assert_match(/either as a Valkey::Search::HybridOptions object or as keyword arguments, not both/, err.message)
  end

  def test_swapped_arms_raise_argument_error
    assert_raises(ArgumentError) { FakeClient.new.ft_hybrid("idx", vsim_arm, search_arm) }
  end

  def test_non_arm_search_arm_raises_argument_error
    assert_raises(ArgumentError) { FakeClient.new.ft_hybrid("idx", "q", vsim_arm) }
  end
end

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

  def test_cursor_commands_send_no_client_side_route
    client = FakeClient.new(cluster_mode: true)
    client.ft_cursor_read("idx", 42)
    assert_nil client.route, "cursor routing is owned by glide-core"
    client.ft_cursor_del("idx", 42)
    assert_nil client.route, "cursor routing is owned by glide-core"
  end

  def batch_client
    client = FakeClient.new
    client.instance_variable_set(:@commands, [])
    client.instance_variable_set(:@futures, [])
    client
  end

  def test_cursor_read_rejected_in_batch
    err = assert_raises(ArgumentError) { batch_client.ft_cursor_read("idx", 42) }
    assert_match(/use Valkey#call to issue FT\.CURSOR READ/, err.message)
  end

  def test_cursor_del_rejected_in_batch
    err = assert_raises(ArgumentError) { batch_client.ft_cursor_del("idx", 42) }
    assert_match(/use Valkey#call to issue FT\.CURSOR DEL/, err.message)
  end

  def test_cursor_read_rejected_in_multi
    client = FakeClient.new
    client.instance_variable_set(:@in_multi, true)
    assert_raises(ArgumentError) { client.ft_cursor_read("idx", 42) }
    assert_raises(ArgumentError) { client.ft_cursor_del("idx", 42) }
  end
end
