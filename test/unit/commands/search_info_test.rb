# frozen_string_literal: true

# Pure unit tests for the Phase 4 Valkey::Search InfoOptions API — scope and
# cluster-flag serialization, and ft_info dispatch (builder path serializes
# options, plain path yields `FT.INFO <index>`).
#
# No server: options are asserted via #to_args, and ft_info against a fake client
# that captures the arguments handed to send_command.
$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require "minitest/autorun"
require "valkey/request_type"
require "valkey/search"
require "valkey/commands/vector_search_commands"

class TestSearchInfo < Minitest::Test
  class FakeClient
    include Valkey::Commands::VectorSearchCommands

    attr_reader :captured_type, :captured_args, :captured_route
    attr_accessor :canned_reply

    def initialize(canned_reply = [])
      @canned_reply = canned_reply
    end

    # Mirrors Valkey#send_command's signature, including the cluster `route:`
    # kwarg that ft_create/ft_drop_index use to broadcast across a cluster.
    def send_command(command_type, command_args = [], route: nil)
      @captured_type = command_type
      @captured_args = command_args
      @captured_route = route
      @canned_reply
    end
  end

  S = Valkey::Search

  # ---- InfoOptions serialization ----

  def test_empty_info_options
    assert_equal [], S::InfoOptions.new.to_args
  end

  def test_info_scope_local
    assert_equal ["LOCAL"], S::InfoOptions.new(scope: :local).to_args
  end

  def test_info_scope_primary
    assert_equal ["PRIMARY"], S::InfoOptions.new(scope: :primary).to_args
  end

  def test_info_scope_cluster
    assert_equal ["CLUSTER"], S::InfoOptions.new(scope: :cluster).to_args
  end

  def test_info_scope_case_insensitive_string
    assert_equal ["CLUSTER"], S::InfoOptions.new(scope: "Cluster").to_args
  end

  def test_info_cluster_flags
    opts = S::InfoOptions.new(scope: :cluster, shard_scope: :all_shards, consistency: :consistent)
    assert_equal %w[CLUSTER ALLSHARDS CONSISTENT], opts.to_args
  end

  def test_info_consistency_only
    assert_equal ["INCONSISTENT"], S::InfoOptions.new(consistency: :inconsistent).to_args
  end

  def test_info_rejects_bad_scope
    err = assert_raises(ArgumentError) { S::InfoOptions.new(scope: :galaxy) }
    assert_match(/unknown info scope/, err.message)
  end

  def test_info_rejects_bad_shard_scope
    assert_raises(ArgumentError) { S::InfoOptions.new(shard_scope: :some) }
  end

  # ---- ft_info dispatch ----

  def test_ft_info_plain
    client = FakeClient.new
    client.ft_info("idx")
    assert_equal Valkey::RequestType::FT_INFO, client.captured_type
    assert_equal ["idx"], client.captured_args
  end

  def test_ft_info_builder_via_options_object
    client = FakeClient.new
    client.ft_info("idx", S::InfoOptions.new(scope: :local))
    assert_equal %w[idx LOCAL], client.captured_args
  end

  def test_ft_info_builder_via_kwargs
    client = FakeClient.new
    client.ft_info("idx", scope: :cluster, consistency: :consistent)
    assert_equal %w[idx CLUSTER CONSISTENT], client.captured_args
  end

  def test_ft_info_rejects_options_and_kwargs
    client = FakeClient.new
    assert_raises(ArgumentError) do
      client.ft_info("idx", S::InfoOptions.new, scope: :local)
    end
  end

  def test_ft_info_rejects_options_and_extra_positional
    client = FakeClient.new
    assert_raises(ArgumentError) do
      client.ft_info("idx", S::InfoOptions.new, "extra")
    end
  end

  def test_ft_info_rejects_non_options_positional
    client = FakeClient.new
    assert_raises(ArgumentError) { client.ft_info("idx", "LOCAL") }
  end
end
