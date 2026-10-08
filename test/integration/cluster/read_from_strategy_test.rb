# frozen_string_literal: true

require "test_helper"

# Tests cluster read-from strategies.
class TestClusterReadFromStrategy < Minitest::Test
  include Helper::Cluster

  KEY = "foo"
  CLIENT_AVAILABILITY_ZONE = "us-east-1a"
  OTHER_AVAILABILITY_ZONE = "us-east-1b"

  def test_az_affinity_all_nodes_routes_to_the_only_matching_primary
    with_availability_zone_affinity_topology do |nodes, _slot_nodes, primary, _replicas|
      availability_zone_by_node = nodes.to_h { |node| [node, OTHER_AVAILABILITY_ZONE] }
      availability_zone_by_node[primary] = CLIENT_AVAILABILITY_ZONE

      assert_get_distribution(
        nodes: nodes,
        availability_zone_by_node: availability_zone_by_node,
        get_calls: 4,
        expected_calls: { primary => 4 }
      )
    end
  end

  def test_az_affinity_all_nodes_splits_reads_between_matching_primary_and_replica
    with_availability_zone_affinity_topology do |nodes, _slot_nodes, primary, replicas|
      matching_replica = replicas.first
      availability_zone_by_node = nodes.to_h { |node| [node, OTHER_AVAILABILITY_ZONE] }
      availability_zone_by_node[primary] = CLIENT_AVAILABILITY_ZONE
      availability_zone_by_node[matching_replica] = CLIENT_AVAILABILITY_ZONE

      assert_get_distribution(
        nodes: nodes,
        availability_zone_by_node: availability_zone_by_node,
        get_calls: 4,
        expected_calls: { primary => 2, matching_replica => 2 }
      )
    end
  end

  def test_az_affinity_all_nodes_falls_back_to_every_slot_node
    with_availability_zone_affinity_topology do |nodes, slot_nodes, _primary, _replicas|
      get_calls = slot_nodes.length * 2

      assert_get_distribution(
        nodes: nodes,
        availability_zone_by_node: nodes.to_h { |node| [node, OTHER_AVAILABILITY_ZONE] },
        get_calls: get_calls,
        expected_calls: slot_nodes.to_h { |node| [node, 2] }
      )
    end
  end

  private

  def with_availability_zone_affinity_topology
    omit_version("8.0.0")

    slot = r.cluster_keyslot(KEY)
    cluster_slots = r.cluster_slots
    slot_range = cluster_slots.find do |range|
      slot.between?(range.fetch("start_slot"), range.fetch("end_slot"))
    end
    skip("No cluster topology entry found for slot #{slot}") unless slot_range

    nodes = addresses_from_cluster_slots(cluster_slots)
    unreachable = nodes.reject { |node| node_reachable?(node) }
    unless unreachable.empty?
      skip("Not every node discovered through CLUSTER SLOTS is reachable: #{unreachable.inspect}")
    end

    primary = address_for(slot_range.fetch("master"))
    replicas = slot_range.fetch("replicas").map { |node| address_for(node) }.uniq
    skip("Slot #{slot} has no reachable replica") if replicas.empty?

    yield nodes, [primary, *replicas].uniq, primary, replicas
  end

  def assert_get_distribution(nodes:, availability_zone_by_node:, get_calls:, expected_calls:)
    previous_availability_zones = snapshot_availability_zones(nodes)
    strategy_client = nil

    begin
      availability_zone_by_node.each do |node, availability_zone|
        set_availability_zone(node, availability_zone)
      end
      strategy_client = _new_client(
        read_from: Valkey::ReadFrom::AZ_AFFINITY_ALL_NODES,
        client_az: CLIENT_AVAILABILITY_ZONE
      )

      before = snapshot_get_calls(nodes)
      get_calls.times { strategy_client.get(KEY) }
      after = snapshot_get_calls(nodes)
      deltas = nodes.to_h { |node| [node, after.fetch(node) - before.fetch(node)] }

      expected = nodes.to_h { |node| [node, expected_calls.fetch(node, 0)] }
      assert_equal expected, deltas
      assert_equal get_calls, deltas.values.sum
    ensure
      cleanup_errors = []
      close_strategy_client(strategy_client, cleanup_errors)
      restore_availability_zones(previous_availability_zones, cleanup_errors)
      raise_cleanup_error(cleanup_errors)
    end
  end

  def addresses_from_cluster_slots(cluster_slots)
    addresses = cluster_slots.flat_map do |range|
      [range.fetch("master"), *range.fetch("replicas")]
    end
    addresses.map { |node| address_for(node) }.uniq
  end

  def address_for(node)
    [node.fetch("ip").to_s, node.fetch("port").to_i]
  end

  def route_to(node)
    Valkey::Route.by_address(*node)
  end

  def node_reachable?(node)
    r.ping(route: route_to(node)) == "PONG"
  rescue Valkey::BaseError
    false
  end

  def snapshot_availability_zones(nodes)
    nodes.to_h do |node|
      config = r.config_get("availability-zone", route: route_to(node))
      [node, config.fetch("availability-zone")]
    end
  end

  def set_availability_zone(node, availability_zone)
    r.config_set("availability-zone", availability_zone, route: route_to(node))
  end

  def snapshot_get_calls(nodes)
    nodes.to_h do |node|
      calls = r.info("commandstats", route: route_to(node)).dig("get", "calls").to_i
      [node, calls]
    end
  end

  # rubocop:disable Naming/RescuedExceptionsVariableName
  def close_strategy_client(client, errors)
    client&.close
  rescue StandardError => error
    errors << "close strategy client: #{error.class}: #{error.message}"
  end

  def restore_availability_zones(previous_availability_zones, errors)
    previous_availability_zones.each do |node, availability_zone|
      set_availability_zone(node, availability_zone)
    rescue StandardError => error
      errors << "restore #{node.join(':')} to #{availability_zone.inspect}: #{error.class}: #{error.message}"
    end
  end
  # rubocop:enable Naming/RescuedExceptionsVariableName

  def raise_cleanup_error(errors)
    return if errors.empty?

    raise "AZ affinity test cleanup failed:\n#{errors.join("\n")}"
  end
end
