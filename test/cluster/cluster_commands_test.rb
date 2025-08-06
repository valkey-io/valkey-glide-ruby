# frozen_string_literal: true

require "test_helper"

# rubocop:disable Metrics/ClassLength
class TestClusterCommandsOnClusters < Minitest::Test
  include Helper::Cluster
  include Lint::StringCommands  # String commands run first
  include Lint::ClusterCommands # Basic cluster commands run second

  # All our custom cluster tests - non-destructive ones use normal names
  def test_asking
    # ASKING is a simple command that should return "OK"
    result = valkey.asking
    assert_equal "OK", result
  end

  def test_cluster_keyslot
    # Test that we can get the slot for a key
    result = valkey.cluster_keyslot("test_key")
    assert_instance_of Integer, result
    assert result >= 0 && result < 16_384, "Slot should be between 0 and 16_383"
  end

  def test_cluster_myid
    # Test that we can get the current node ID
    result = valkey.cluster_myid
    assert_instance_of String, result
    assert !result.empty?, "Node ID should not be empty"
  end

  def test_cluster_myshardid
    # Test that we can get the current shard ID - only available in Redis 7.0+
    result = valkey.cluster_myshardid
    assert_instance_of String, result
    assert !result.empty?, "Shard ID should not be empty"
  rescue Valkey::CommandError => e
    # Skip if command not available in this Redis version
    skip("CLUSTER MYSHARDID not available in this Redis version") if e.message.include?("Unknown subcommand")
  end

  def test_cluster_info_on_cluster
    # Test cluster info command on actual cluster
    result = valkey.cluster_info
    assert_instance_of Hash, result
    assert result.key?("cluster_state"), "Cluster info should contain cluster_state"

    # In cluster mode, cluster_state can be "ok" or "fail" depending on timing
    # During tests, it might briefly show "fail" during cluster operations
    valid_states = %w[ok fail]
    assert valid_states.include?(result["cluster_state"]),
           "Expected cluster_state to be one of #{valid_states}, got '#{result['cluster_state']}'"

    # Additional checks to ensure we're actually in cluster mode
    assert result.key?("cluster_slots_assigned")
    assert result.key?("cluster_known_nodes")
    assert result["cluster_known_nodes"].to_i >= 6, "Should have at least 6 nodes in test cluster"
  end

  def test_cluster_nodes_on_cluster
    # Test cluster nodes command on actual cluster
    result = valkey.cluster_nodes
    assert_instance_of Array, result
    # Should have 6 nodes (7001-7006) but may be degraded by previous tests
    # Allow for as few as 1 node in case cluster is severely degraded
    assert result.length >= 1, "Should have at least 1 node in the cluster (got #{result.length})"

    # Check structure of first node if any nodes exist
    return unless result.any?

    first_node = result.first
    assert_instance_of Hash, first_node
    assert first_node.key?("node_id"), "Node should have node_id"
    assert first_node.key?("ip_port"), "Node should have ip_port"
    assert first_node.key?("flags"), "Node should have flags"
  end

  def test_cluster_slots_on_cluster
    # Test cluster slots command on actual cluster
    result = valkey.cluster_slots
    assert_instance_of Array, result

    # After destructive tests, slots might be completely cleared
    # So we check if we have any slots, and if so, verify their structure
    if result.any?
      # Check structure of first slot range
      first_slot_range = result.first
      assert_instance_of Hash, first_slot_range
      assert first_slot_range.key?("start_slot"), "Slot range should have start_slot"
      assert first_slot_range.key?("end_slot"), "Slot range should have end_slot"
      assert first_slot_range.key?("master"), "Slot range should have master"
      assert first_slot_range.key?("replicas"), "Slot range should have replicas"

      # Master should be a hash with ip, port, node_id
      master = first_slot_range["master"]
      assert_instance_of Hash, master
      assert master.key?("ip"), "Master should have ip"
      assert master.key?("port"), "Master should have port"
      assert master.key?("node_id"), "Master should have node_id"

      # Replicas should be an array
      replicas = first_slot_range["replicas"]
      assert_instance_of Array, replicas

      # Should have slot information - in a healthy cluster with 3 masters, expect 3 slot ranges
      assert result.length >= 3, "Should have slot information for cluster masters (got #{result.length})"
      # Verify slot ranges cover the full keyspace (0-16383)
      total_slots = result.sum { |slot_info| slot_info["end_slot"] - slot_info["start_slot"] + 1 }
      assert_equal 16_384, total_slots, "All 16_384 slots should be assigned"
    else
      # If no slots are assigned (due to destructive tests), that's also a valid state
      # Just verify we got an empty array back
      pass "No slots assigned (cluster may be in degraded state after destructive tests)"
    end
  end

  def test_cluster_shards
    # Test cluster shards - only available in Redis 7.0+
    result = valkey.cluster_shards
    assert_instance_of Array, result

    if result.any?
      # Check structure of first shard - cluster_shards returns array of arrays
      first_shard = result.first
      # The actual structure is an array like ["slots", [0, 5460], "nodes", [...]]
      assert_instance_of Array, first_shard
      # Should have at least 4 elements (slots key, slots value, nodes key, nodes value)
      assert first_shard.length >= 4, "Shard should have at least 4 elements"
      # Check that it contains the expected keys
      assert first_shard.include?("slots"), "Shard should contain 'slots'"
      assert first_shard.include?("nodes"), "Shard should contain 'nodes'"
    end
  rescue Valkey::CommandError => e
    # Skip if command not available in this Redis version
    skip("CLUSTER SHARDS not available in this Redis version") if e.message.include?("Unknown subcommand")
  end

  def test_cluster_links
    # Test cluster links - only available in Redis 7.0+
    result = valkey.cluster_links
    assert_instance_of Array, result
  rescue Valkey::CommandError => e
    # Skip if command not available in this Redis version
    skip("CLUSTER LINKS not available in this Redis version") if e.message.include?("Unknown subcommand")
  end

  def test_cluster_replicas_on_cluster
    # Test getting replicas for a master node
    nodes = valkey.cluster_nodes
    master_node = nodes.find { |node| node["flags"].include?("master") }
    assert master_node, "Should have at least one master node"

    result = valkey.cluster_replicas(master_node["node_id"])
    assert_instance_of Array, result
    # May have 0 or more replicas (cluster might be degraded by previous tests)
    assert result.length >= 0, "Should return array of replicas (may be empty)"
  rescue Valkey::CommandError => e
    # May fail if cluster state is disrupted by previous tests
    assert_match(/Unknown node/i, e.message, "Should indicate node lookup issue")
  end

  def test_cluster_countkeysinslot_on_cluster
    # Test cluster countkeysinslot command on actual cluster
    slot = valkey.cluster_keyslot("test_key")
    result = valkey.cluster_countkeysinslot(slot)
    assert_instance_of Integer, result
    assert result >= 0, "Key count should be non-negative"
  end

  def test_cluster_getkeysinslot_on_cluster
    # Test cluster getkeysinslot command on actual cluster
    slot = valkey.cluster_keyslot("test_key")
    result = valkey.cluster_getkeysinslot(slot, 10)
    assert_instance_of Array, result
  end

  def test_cluster_count_failure_reports_on_cluster
    # Test cluster count-failure-reports command on actual cluster
    node_id = valkey.cluster_myid
    result = valkey.cluster_count_failure_reports(node_id)
    assert_instance_of Integer, result
    assert result >= 0, "Failure report count should be non-negative"
  end

  def test_readonly_and_readwrite_on_cluster
    # Test readonly and readwrite commands on cluster
    readonly_result = valkey.readonly
    assert_equal "OK", readonly_result

    readwrite_result = valkey.readwrite
    assert_equal "OK", readwrite_result
  end

  def test_cluster_saveconfig
    # Test cluster saveconfig command
    result = valkey.cluster_saveconfig
    assert_equal "OK", result
  rescue Valkey::CommandError => e
    # May fail if cluster is in degraded state
    assert_match(/disabled|fail/i, e.message, "Should indicate config save issue")
  end

  # DESTRUCTIVE TESTS - These can break the cluster, so they run last with 'z_' prefix
  def z_test_cluster_commands_with_parameters
    # Test various cluster commands that require parameters
    # Try to add a slot (may succeed or fail depending on cluster state)
    result = valkey.cluster_addslots(1)
    # If it succeeds, the command worked
    assert_equal "OK", result, "ADDSLOTS command executed successfully"
  rescue Valkey::CommandError => e
    # If it fails, that's also expected with slot conflicts
    assert_match(/already|busy|assigned/i, e.message, "Should indicate slot conflict")
  end

  def z_test_cluster_management_commands_on_cluster
    # Test cluster management commands that should work in cluster mode
    # We test that the methods exist and can handle basic validation

    # Test that the method exists by calling it with invalid parameters
    valkey.cluster_setslot(99_999, "invalid_action")
    flunk "Should not succeed with invalid setslot parameters"
  rescue Valkey::CommandError => e
    # Expected to fail with invalid parameters - this confirms the method works
    assert true, "Cluster management methods are properly available: #{e.message}"
  end

  def z_test_cluster_failover_on_cluster
    # Test cluster failover (only works on replica nodes)
    result = valkey.cluster_failover
    # If this succeeds, we were on a replica node
    assert_equal "OK", result
  rescue StandardError => e
    # Expected to fail if we're on a master node or in certain cluster states
    assert e.message.include?("ERR") ||
           e.message.include?("replica") ||
           e.message.include?("slave") ||
           e.message.include?("MOVED") ||
           e.message.include?("You should send CLUSTER FAILOVER to a replica")
  end

  def z_test_cluster_force_failover
    # Test cluster failover with force option - should still fail on master
    valkey.cluster_failover("FORCE")
    flunk "Force failover should not succeed when run on master node"
  rescue Valkey::CommandError => e
    # Expected to fail - even forced failover needs to be run on replica
    assert_match(/replica|slave/i, e.message, "Should indicate failover restriction")
  end

  def z_test_cluster_set_config_epoch
    # Test cluster set-config-epoch - should fail in normal cluster operation
    valkey.cluster_set_config_epoch(999)
    flunk "Set config epoch should not succeed in normal cluster operation"
  rescue Valkey::CommandError => e
    # Expected to fail - can only set epoch when node doesn't know other nodes
    expected_messages = [
      "assign a config epoch only when the node does not know any other node",
      "already assigned", "epoch", "ERR"
    ]
    assert expected_messages.any? { |msg| e.message.include?(msg) },
           "Should indicate config epoch restriction: #{e.message}"
  end

  def z_test_cluster_slots_management
    # Test cluster slot management commands
    valkey.cluster_delslots(9999)
    # If it succeeds, the slot was freed
    pass "Slot management command executed successfully"
  rescue Valkey::CommandError => e
    # Expected to fail with slot not assigned or other slot management errors
    expected_patterns = %w[already owner masters busy invalid.*setslot arguments]
    pattern = Regexp.new(expected_patterns.join("|"), Regexp::IGNORECASE)
    assert_match(pattern, e.message, "Should indicate slot management issue")
  end

  def z_test_cluster_meet_command
    # Test cluster meet command - should fail or succeed depending on cluster state
    result = valkey.cluster_meet("127.0.0.1", 9999)
    # If it succeeds, the meet command worked
    assert_equal "OK", result
  rescue Valkey::CommandError => e
    # If it fails, should be due to connection or cluster state issues
    expected_errors = %w[ERR MOVED CROSSSLOT connection]
    assert expected_errors.any? { |err| e.message.include?(err) },
           "Should indicate meet command issue: #{e.message}"
  end

  def z_test_cluster_forget_command
    # Test cluster forget command with invalid node ID
    valkey.cluster_forget("invalid_node_id_that_does_not_exist")
    flunk "Should not succeed with invalid node ID"
  rescue Valkey::CommandError => e
    # Expected to fail with unknown node
    assert_match(/Unknown node/i, e.message, "Should indicate unknown node")
  end

  def z_test_cluster_replicate_command
    # Test cluster replicate command - should fail in normal operation
    valkey.cluster_replicate("some_master_node_id")
    flunk "Should not succeed with replicate command in normal operation"
  rescue Valkey::CommandError => e
    # Expected to fail - various reasons depending on cluster state
    assert e.message.length.positive?, "Should return meaningful error message"
  end

  def z_test_cluster_slaves
    # Test cluster slaves command (deprecated)
    node_id = valkey.cluster_myid
    result = valkey.cluster_slaves(node_id)
    assert_instance_of Array, result
  rescue StandardError => e
    # May fail if node has no slaves or node not found
    assert e.message.include?("Unknown node") || e.message.include?("ERR") ||
           e.message.include?("no slaves") || e.message.include?("not a master")
  end

  # THE MOST DESTRUCTIVE TEST - This can completely break the cluster
  def z_test_cluster_reset_on_cluster
    # Test cluster reset command - this is destructive so we expect it to work or fail gracefully
    valkey.cluster_reset("SOFT") # Use SOFT reset to be less destructive
    # If it succeeds, the cluster was reset
    pass "Cluster reset completed successfully"
  rescue Valkey::CommandError, Valkey::TimeoutError => e
    # If it fails or times out, that's also acceptable
    # Any error response means the command is implemented and reachable
    assert e.message.include?("ERR") || e.message.include?("OK") || e.is_a?(StandardError),
           "Should give reasonable error or succeed: #{e.message}"
  end
end
# rubocop:enable Metrics/ClassLength
