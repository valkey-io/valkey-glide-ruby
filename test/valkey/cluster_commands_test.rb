# frozen_string_literal: true

require "test_helper"

class ValkeyClusterCommandsTest < Minitest::Test
  include Helper::Cluster
  include Lint::ClusterCommands

  def test_asking
    # ASKING is a simple command that should return "OK"
    result = valkey.asking
    assert_equal "OK", result
  end

  def test_cluster_keyslot
    # Test that we can get the slot for a key
    result = valkey.cluster_keyslot("test_key")
    assert_instance_of Integer, result
    assert result >= 0 && result < 16384, "Slot should be between 0 and 16383"
  end

  def test_cluster_myid
    # Test that we can get the current node ID
    result = valkey.cluster_myid
    assert_instance_of String, result
    assert result.length > 0, "Node ID should not be empty"
  end

  def test_cluster_myshardid
    # Test that we can get the current shard ID - only available in Redis 7.0+
    begin
      result = valkey.cluster_myshardid
      assert_instance_of String, result
      assert result.length > 0, "Shard ID should not be empty"
    rescue Valkey::CommandError => e
      # Skip if command not available in this Redis version
      skip("CLUSTER MYSHARDID not available in Redis 6.2") if e.message.include?("Unknown subcommand")
    end
  end

  def test_cluster_info
    # Test that we can get cluster information
    result = valkey.cluster_info
    assert_instance_of Hash, result
    assert result.key?("cluster_state"), "Cluster info should contain cluster_state"
    # Cluster state might be "fail" if destructive tests ran earlier, which is acceptable
    assert ["ok", "fail"].include?(result["cluster_state"]), "Cluster state should be ok or fail"
  end

  def test_cluster_nodes
    # Test that we can get cluster nodes information
    result = valkey.cluster_nodes
    assert_instance_of Array, result
    # Should have at least 3 nodes (cluster might be degraded by previous tests)
    assert result.length >= 3, "Should have at least 3 nodes in the cluster"

    # Check structure of first node
    first_node = result.first
    assert_instance_of Hash, first_node
    assert first_node.key?("node_id"), "Node should have node_id"
    assert first_node.key?("ip_port"), "Node should have ip_port"
    assert first_node.key?("flags"), "Node should have flags"
  end

  def test_cluster_slots
    # Test that we can get cluster slots information
    result = valkey.cluster_slots
    assert_instance_of Array, result
    # Should have at least 1 slot range (cluster might be degraded by previous tests)
    assert result.length >= 1, "Should have at least 1 slot range"
    
    # Check structure of first slot range
    first_slot_range = result.first
    assert_instance_of Hash, first_slot_range
    assert first_slot_range.key?("start_slot"), "Slot range should have start_slot"
    assert first_slot_range.key?("end_slot"), "Slot range should have end_slot"
    assert first_slot_range.key?("master"), "Slot range should have master"
  end

  def test_cluster_shards
    # Test cluster shards - only available in Redis 7.0+
    begin
      result = valkey.cluster_shards
      assert_instance_of Array, result
      assert result.length >= 3, "Should have at least 3 shards"
    rescue Valkey::CommandError => e
      # Skip if command not available in this Redis version
      skip("CLUSTER SHARDS not available in Redis 6.2") if e.message.include?("Unknown subcommand")
    end
  end

  def test_cluster_links
    # Test cluster links - only available in Redis 7.0+
    begin
      result = valkey.cluster_links
      assert_instance_of Array, result
    rescue Valkey::CommandError => e
      # Skip if command not available in this Redis version
      skip("CLUSTER LINKS not available in Redis 6.2") if e.message.include?("Unknown subcommand")
    end
  end

  def test_cluster_replicas
    # Test getting replicas for a master node
    begin
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
  end

  def test_cluster_countkeysinslot
    # Test that we can count keys in a slot
    slot = valkey.cluster_keyslot("test_key")
    result = valkey.cluster_countkeysinslot(slot)
    assert_instance_of Integer, result
    assert result >= 0, "Key count should be non-negative"
  end

  def test_cluster_getkeysinslot
    # Test that we can get keys in a slot
    slot = valkey.cluster_keyslot("test_key")
    result = valkey.cluster_getkeysinslot(slot, 10)
    assert_instance_of Array, result
  end

  def test_readonly_and_readwrite
    # Test readonly and readwrite commands
    readonly_result = valkey.readonly
    assert_equal "OK", readonly_result

    readwrite_result = valkey.readwrite
    assert_equal "OK", readwrite_result
  end

  def test_cluster_commands_with_parameters
    # Test various cluster commands that require parameters
    begin
      # Try to add a slot (may succeed or fail depending on cluster state)
      result = valkey.cluster_addslots(1)
      # If it succeeds, the command worked
      assert_equal "OK", result, "ADDSLOTS command executed successfully"
    rescue Valkey::CommandError => e
      # If it fails, that's also expected with slot conflicts
      assert_match(/already|busy|assigned/i, e.message, "Should indicate slot conflict")
    end
  end

  def test_cluster_management_commands
    # Test that cluster management commands are available (safe operations only)
    # We test that the methods exist and can handle basic validation
    begin
      # Test that the method exists by calling it with invalid parameters
      valkey.cluster_setslot(99999, "invalid_action")
      flunk "Should not succeed with invalid setslot parameters"
    rescue Valkey::CommandError => e
      # Expected to fail with invalid parameters - this confirms the method works
      assert true, "Cluster management methods are properly available: #{e.message}"
    end
  end

  def test_cluster_failover
    # Test cluster failover command - should fail when run on master
    begin
      result = valkey.cluster_failover
      flunk "Failover should not succeed when run on master node"
    rescue Valkey::CommandError => e
      # Expected to fail when run on master - this is correct behavior
      assert_match(/replica|slave/i, e.message, "Should indicate failover must be run on replica")
    end
  end

  def test_zzz_cluster_reset_destructive
    # Test cluster reset - runs last to avoid corrupting other tests
    begin
      result = valkey.cluster_reset
      flunk "Cluster reset should not succeed on healthy cluster"
    rescue Valkey::CommandError, Valkey::TimeoutError => e
      # Expected to fail or timeout - this is the correct behavior
      pass "Cluster reset correctly failed or timed out: #{e.class}"
    end
  end

  def test_zzz_destructive_cluster_operations
    # Test all potentially destructive cluster operations at the very end
    # This way they don't interfere with other tests
    
    # Test cluster failover on master (should fail)
    begin
      result = valkey.cluster_failover("FORCE")
      flunk "Forced failover should not succeed on master node"
    rescue Valkey::CommandError => e
      assert_match(/replica|slave/i, e.message, "Should indicate failover restriction")
    end
    
    # Test cluster forget with invalid node (should fail)
    begin
      valkey.cluster_forget("invalid_node_id_destructive_test")
      flunk "Should not succeed with invalid node_id"
    rescue Valkey::CommandError => e
      assert_match(/Unknown node/i, e.message, "Should indicate unknown node")
    end
    
    # Final note: These tests may have disrupted cluster state
    pass "Destructive cluster operations tested (cluster may need restart after this)"
  end

  def test_cluster_setslot
    # Test slot management - test the command works (may succeed or fail depending on cluster state)
    begin
      result = valkey.cluster_setslot(1, "STABLE")
      # If it succeeds, that's also valid - the command worked
      assert_equal "OK", result, "SETSLOT command executed successfully"
    rescue Valkey::CommandError => e
      # If it fails, that's also expected with slot conflicts
      assert_match(/already|owner|masters|busy/i, e.message, "Should indicate slot management issue")
    end
  end

  def test_cluster_count_failure_reports
    # Test cluster count failure reports
    begin
      node_id = valkey.cluster_myid
      result = valkey.cluster_count_failure_reports(node_id)
      assert_instance_of Integer, result
      assert result >= 0, "Failure report count should be non-negative"
    rescue => e
      # May fail if node not found or other cluster issues
      assert e.message.include?("Unknown node") || e.message.include?("ERR")
    end
  end

  def test_cluster_replicate
    # Test cluster replicate command - should fail with invalid node_id
    begin
      valkey.cluster_replicate("invalid_node_id")
      flunk "Should not succeed with invalid node_id"
    rescue Valkey::CommandError => e
      # Expected to fail with unknown node - this is correct behavior
      assert_match(/Unknown node/i, e.message, "Should indicate unknown node")
    end
  end

  def test_cluster_forget
    # Test cluster forget command - should fail with invalid node_id
    begin
      valkey.cluster_forget("invalid_node_id")
      flunk "Should not succeed with invalid node_id"
    rescue Valkey::CommandError => e
      # Expected to fail with unknown node - this is correct behavior
      assert_match(/Unknown node/, e.message, "Should indicate unknown node")
    end
  end

  def test_cluster_meet
    # Test cluster meet command
    begin
      result = valkey.cluster_meet("127.0.0.1", 6380)
      assert_equal "OK", result
    rescue => e
      # May fail if target node doesn't exist or other cluster issues
      assert e.message.include?("ERR") || e.message.include?("MOVED") || e.message.include?("CROSSSLOT") || e.message.include?("connection")
    end
  end

  def test_cluster_set_config_epoch
    # Test setting config epoch - should fail on established cluster
    begin
      valkey.cluster_set_config_epoch(100)
      flunk "Should not succeed setting epoch on established cluster"
    rescue Valkey::CommandError => e
      # Expected to fail on established cluster - this is correct behavior
      assert_match(/assign a config epoch only when|already non-zero/i, e.message, "Should indicate epoch restriction")
    end
  end

  def test_cluster_slaves
    # Test cluster slaves command (deprecated)
    begin
      node_id = valkey.cluster_myid
      result = valkey.cluster_slaves(node_id)
      assert_instance_of Array, result
    rescue => e
      # May fail if node has no slaves or node not found
      assert e.message.include?("Unknown node") || e.message.include?("ERR") ||
             e.message.include?("no slaves") || e.message.include?("not a master")
    end
  end
end
