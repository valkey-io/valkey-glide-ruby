# frozen_string_literal: true

require "test_helper"

# Integration tests for cluster routing support.
# Modeled after Go's integTest/cluster_commands_test.go routing tests.
# Requires a 6-node cluster running on 127.0.0.1:7000-7005.
class TestClusterRouting < Minitest::Test
  include Helper::Cluster

  # --- CustomCommand via call/call_v with routing ---

  def test_custom_command_info_all_primaries
    result = r.call("INFO", route: Valkey::Route.all_primaries)

    assert_kind_of Hash, result
    result.each_value do |info|
      assert_includes info.downcase, "# stats"
    end
  end

  def test_custom_command_echo_random
    result = r.call("ECHO", "GO GLIDE GO", route: Valkey::Route.random)

    assert_equal "GO GLIDE GO", result
  end

  def test_custom_command_ping_all_nodes
    result = r.call("PING", route: Valkey::Route.all_nodes)

    assert_equal "PONG", result
  end

  def test_custom_command_dbsize_random
    result = r.call("DBSIZE", route: Valkey::Route.random)

    assert_kind_of Integer, result
    assert_operator result, :>=, 0
  end

  def test_custom_command_dbsize_all_primaries
    result = r.call("DBSIZE", route: Valkey::Route.all_primaries)

    assert_kind_of Integer, result
    assert_operator result, :>=, 0
  end

  def test_custom_command_config_get_random
    result = r.call("CONFIG", "GET", "*file", route: Valkey::Route.random)

    assert_kind_of Hash, result
  end

  def test_custom_command_config_get_all_primaries
    result = r.call("CONFIG", "GET", "*file", route: Valkey::Route.all_primaries)

    assert_kind_of Hash, result
    assert_operator result.size, :>, 0
  end

  def test_custom_command_invalid_route
    assert_raises(Valkey::CommandError, Valkey::ConnectionError) do
      r.call("PING", route: Valkey::Route.by_address("invalidHost", 9999))
    end
  end

  def test_call_v_with_route
    result = r.call_v(%w[ECHO hello], route: Valkey::Route.random)

    assert_equal "hello", result
  end

  # --- ping ---

  def test_ping_no_route
    result = r.ping
    assert_equal "PONG", result
  end

  def test_ping_with_message_and_route
    result = r.ping("hello", route: Valkey::Route.all_nodes)

    assert_equal "hello", result
  end

  def test_ping_invalid_route
    assert_raises(Valkey::CommandError, Valkey::ConnectionError) do
      r.ping(route: Valkey::Route.by_address("invalidHost", 9999))
    end
  end

  # --- echo ---

  def test_echo_random_route
    result = r.echo("hello", route: Valkey::Route.random)

    assert_equal "hello", result
  end

  def test_echo_all_primaries_route
    result = r.echo("hello", route: Valkey::Route.all_primaries)

    assert_kind_of Hash, result
    result.each_value do |msg|
      assert_equal "hello", msg
    end
  end

  # --- time ---

  def test_time_without_route
    result = r.time

    assert_kind_of Array, result
    assert_equal 2, result.size
  end

  def test_time_random_route
    result = r.time(route: Valkey::Route.random)

    assert_kind_of Array, result
    assert_equal 2, result.size
  end

  def test_time_all_nodes_route
    result = r.time(route: Valkey::Route.all_nodes)

    assert_kind_of Hash, result
    assert_operator result.size, :>, 1
    result.each_value do |time_val|
      assert_kind_of Array, time_val
    end
  end

  def test_time_invalid_route
    assert_raises(Valkey::CommandError, Valkey::ConnectionError) do
      r.time(route: Valkey::Route.by_address("invalidHost", 9999))
    end
  end

  # --- dbsize ---

  def test_dbsize_random_route
    result = r.dbsize(route: Valkey::Route.random)

    assert_kind_of Integer, result
    assert_operator result, :>=, 0
  end

  def test_dbsize_without_route
    result = r.dbsize
    assert_kind_of Integer, result
  end

  # --- info ---

  def test_info_with_random_route
    result = r.info("server", route: Valkey::Route.random)

    assert_kind_of Hash, result
  end

  def test_info_with_all_primaries_route
    result = r.info("server", route: Valkey::Route.all_primaries)

    assert_kind_of Hash, result
    assert_operator result.size, :>=, 3
    # Each node's value should be a parsed Hash (not raw string)
    result.each_value do |v|
      assert_kind_of Hash, v
      assert v.key?("tcp_port")
    end
  end

  def test_info_without_route
    result = r.info
    assert_kind_of Hash, result
  end

  # --- config ---

  def test_config_get_with_random_route
    result = r.config_get("maxmemory", route: Valkey::Route.random)

    assert_kind_of Hash, result
    assert result.key?("maxmemory")
  end

  def test_config_get_with_all_primaries_route
    result = r.config_get("maxmemory", route: Valkey::Route.all_primaries)

    assert_kind_of Hash, result
    result.each_value do |v|
      assert_kind_of Hash, v
      assert v.key?("maxmemory")
    end
  end

  def test_config_resetstat_with_all_primaries_route
    result = r.config_resetstat(route: Valkey::Route.all_primaries)

    assert_equal "OK", result
  end

  # --- flushall ---

  def test_flushall_with_all_primaries_route
    result = r.flushall(nil, route: Valkey::Route.all_primaries)

    assert_equal "OK", result
  end

  # --- lolwut ---

  def test_lolwut_with_random_route
    result = r.lolwut(route: Valkey::Route.random)

    assert_kind_of String, result
  end

  # --- client_id ---

  def test_client_id_random_route
    result = r.client_id(route: Valkey::Route.random)

    assert_kind_of Integer, result
    assert_operator result, :>, 0
  end

  def test_client_id_all_primaries_route
    result = r.client_id(route: Valkey::Route.all_primaries)

    assert_kind_of Hash, result
    result.each_value do |id|
      assert_kind_of Integer, id
      assert_operator id, :>, 0
    end
  end

  # --- cluster_info ---

  def test_cluster_info_without_route
    result = r.cluster_info

    assert_kind_of Hash, result
    assert result.key?("cluster_state")
  end

  def test_cluster_info_random_route
    result = r.cluster_info(route: Valkey::Route.random)

    assert_kind_of Hash, result
  end

  def test_cluster_info_all_nodes_route
    result = r.cluster_info(route: Valkey::Route.all_nodes)

    assert_kind_of Hash, result
    result.each_value do |v|
      assert_kind_of Hash, v
      assert v.key?("cluster_state")
    end
  end

  # --- cluster_nodes ---

  def test_cluster_nodes_random_route
    result = r.cluster_nodes(route: Valkey::Route.random)

    assert_kind_of Array, result
    assert_operator result.size, :>, 0
  end

  def test_cluster_nodes_all_nodes_route
    result = r.cluster_nodes(route: Valkey::Route.all_nodes)

    assert_kind_of Hash, result
    result.each_value do |v|
      refute_nil v
    end
  end

  # --- cluster_myid ---

  def test_cluster_myid_all_primaries_route
    result = r.cluster_myid(route: Valkey::Route.all_primaries)

    assert_kind_of Hash, result
    result.each_value do |id|
      assert_kind_of String, id
      refute_empty id
    end
  end

  def test_cluster_myid_random_route
    result = r.cluster_myid(route: Valkey::Route.random)

    assert_kind_of String, result
    refute_empty result
  end

  # --- randomkey ---

  def test_randomkey_with_route
    # Ensure at least one key exists on some node
    r.set("routing_test_rk", "val")
    # randomkey with route may return nil if the routed node has no keys
    result = r.randomkey(route: Valkey::Route.random)
    assert(result.nil? || result.is_a?(String))
  end

  # --- lastsave ---

  def test_lastsave_random_route
    result = r.lastsave(route: Valkey::Route.random)

    assert_kind_of Integer, result
    assert_operator result, :>, 0
  end

  private

  def r
    @r ||= _new_client
  end
end
