# frozen_string_literal: true

require "test_helper"

# Integration tests for cluster routing support.
# Requires a 6-node cluster running on 127.0.0.1:7000-7005.
class TestClusterRouting < Minitest::Test
  include Helper::Cluster

  # --- ping ---

  def test_ping_with_random_route
    result = r.ping(route: Valkey::Route.random)

    assert_instance_of Valkey::ClusterValue, result
    assert result.single_node?
    assert_equal "PONG", result.single_value
  end

  def test_ping_with_all_nodes_route
    result = r.ping(route: Valkey::Route.all_nodes)

    assert_instance_of Valkey::ClusterValue, result
    assert result.multi_node?
    assert_kind_of Hash, result.multi_value
    result.multi_value.each_value do |v|
      assert_equal "PONG", v
    end
  end

  def test_ping_with_all_primaries_route
    result = r.ping(route: Valkey::Route.all_primaries)

    assert_instance_of Valkey::ClusterValue, result
    assert result.multi_node?
    assert_kind_of Hash, result.multi_value
    assert_operator result.multi_value.size, :>=, 3 # at least 3 primaries
    result.multi_value.each_value do |v|
      assert_equal "PONG", v
    end
  end

  def test_ping_with_message_and_route
    result = r.ping("hello", route: Valkey::Route.random)

    assert_instance_of Valkey::ClusterValue, result
    assert result.single_node?
    assert_equal "hello", result.single_value
  end

  def test_ping_without_route_returns_plain_value
    result = r.ping

    assert_equal "PONG", result
    refute_instance_of Valkey::ClusterValue, result
  end

  # --- dbsize ---

  def test_dbsize_with_all_primaries_route
    # Ensure at least one key exists
    r.set("routing_test_key", "value")

    result = r.dbsize(route: Valkey::Route.all_primaries)

    assert_instance_of Valkey::ClusterValue, result
    assert result.multi_node?
    assert_kind_of Hash, result.multi_value
    result.multi_value.each_value do |v|
      assert_kind_of Integer, v
      assert_operator v, :>=, 0
    end
  end

  def test_dbsize_with_random_route
    result = r.dbsize(route: Valkey::Route.random)

    assert_instance_of Valkey::ClusterValue, result
    assert result.single_node?
    assert_kind_of Integer, result.single_value
  end

  def test_dbsize_without_route_returns_integer
    result = r.dbsize

    assert_kind_of Integer, result
    refute_instance_of Valkey::ClusterValue, result
  end

  # --- info ---

  def test_info_with_all_primaries_route
    result = r.info("server", route: Valkey::Route.all_primaries)

    assert_instance_of Valkey::ClusterValue, result
    assert result.multi_node?
    assert_kind_of Hash, result.multi_value
    assert_operator result.multi_value.size, :>=, 3
  end

  def test_info_with_random_route
    result = r.info("server", route: Valkey::Route.random)

    assert_instance_of Valkey::ClusterValue, result
    assert result.single_node?
  end

  def test_info_without_route_returns_hash
    result = r.info

    assert_kind_of Hash, result
    refute_instance_of Valkey::ClusterValue, result
  end

  # --- time ---

  def test_time_with_random_route
    result = r.time(route: Valkey::Route.random)

    assert_instance_of Valkey::ClusterValue, result
    assert result.single_node?
    assert_kind_of Array, result.single_value
    assert_equal 2, result.single_value.size
  end

  def test_time_with_all_primaries_route
    result = r.time(route: Valkey::Route.all_primaries)

    assert_instance_of Valkey::ClusterValue, result
    assert result.multi_node?
    assert_kind_of Hash, result.multi_value
  end

  # --- config ---

  def test_config_get_with_route
    result = r.config_get("maxmemory", route: Valkey::Route.random)

    assert_instance_of Valkey::ClusterValue, result
    assert result.single_node?
  end

  def test_config_resetstat_with_route
    result = r.config_resetstat(route: Valkey::Route.all_primaries)

    assert_instance_of Valkey::ClusterValue, result
    assert result.multi_node?
  end

  # --- flushall / flushdb ---

  def test_flushall_with_route
    result = r.flushall(nil, route: Valkey::Route.all_primaries)

    assert_instance_of Valkey::ClusterValue, result
    assert result.multi_node?
  end

  # --- lolwut ---

  def test_lolwut_with_random_route
    result = r.lolwut(route: Valkey::Route.random)

    assert_instance_of Valkey::ClusterValue, result
    assert result.single_node?
    assert_kind_of String, result.single_value
  end

  # --- client_id ---

  def test_client_id_with_all_primaries_route
    result = r.client_id(route: Valkey::Route.all_primaries)

    assert_instance_of Valkey::ClusterValue, result
    assert result.multi_node?
    assert_kind_of Hash, result.multi_value
    result.multi_value.each_value do |v|
      assert_kind_of Integer, v
      assert_operator v, :>, 0
    end
  end

  # --- call / call_v ---

  def test_call_with_route
    result = r.call("PING", route: Valkey::Route.random)

    assert_instance_of Valkey::ClusterValue, result
    assert result.single_node?
    assert_equal "PONG", result.single_value
  end

  def test_call_v_with_route
    result = r.call_v(["PING"], route: Valkey::Route.all_primaries)

    assert_instance_of Valkey::ClusterValue, result
    assert result.multi_node?
    assert_kind_of Hash, result.multi_value
  end

  # --- cluster commands ---

  def test_cluster_info_with_route
    result = r.cluster_info(route: Valkey::Route.random)

    assert_instance_of Valkey::ClusterValue, result
    assert result.single_node?
  end

  def test_cluster_myid_with_route
    result = r.cluster_myid(route: Valkey::Route.all_primaries)

    assert_instance_of Valkey::ClusterValue, result
    assert result.multi_node?
    assert_kind_of Hash, result.multi_value
    result.multi_value.each_value do |v|
      assert_kind_of String, v
      refute_empty v
    end
  end

  private

  def r
    @r ||= _new_client
  end
end
