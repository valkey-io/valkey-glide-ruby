# frozen_string_literal: true

require "test_helper"

# Unit tests for Valkey::Route and Valkey::ClusterValue classes.
# These do not require a running server — they test the Ruby layer only.
class TestRouteUnit < Minitest::Test
  def test_all_nodes_route
    route = Valkey::Route.all_nodes
    assert route.multi_node?
    refute route.single_node? if route.respond_to?(:single_node?)
  end

  def test_all_primaries_route
    route = Valkey::Route.all_primaries
    assert route.multi_node?
  end

  def test_random_route
    route = Valkey::Route.random
    refute route.multi_node?
  end

  def test_slot_id_route_primary
    route = Valkey::Route.slot_id(1234, :primary)
    refute route.multi_node?
  end

  def test_slot_id_route_replica
    route = Valkey::Route.slot_id(5000, :replica)
    refute route.multi_node?
  end

  def test_slot_key_route
    route = Valkey::Route.slot_key("mykey")
    refute route.multi_node?
  end

  def test_slot_key_route_replica
    route = Valkey::Route.slot_key("mykey", :replica)
    refute route.multi_node?
  end

  def test_by_address_route
    route = Valkey::Route.by_address("10.0.0.1", 6379)
    refute route.multi_node?
  end

  def test_cluster_value_single_node
    cv = Valkey::ClusterValue.new("PONG", multi_node: false)

    assert cv.single_node?
    refute cv.multi_node?
    assert_equal "PONG", cv.single_value
    assert_equal "PONG", cv.value
  end

  def test_cluster_value_multi_node
    data = { "node1:6379" => 120, "node2:6379" => 98 }
    cv = Valkey::ClusterValue.new(data, multi_node: true)

    assert cv.multi_node?
    refute cv.single_node?
    assert_equal data, cv.multi_value
    assert_equal data, cv.value
  end

  def test_cluster_value_nil_value
    cv = Valkey::ClusterValue.new(nil, multi_node: false)

    assert cv.single_node?
    assert_nil cv.single_value
  end
end
