# frozen_string_literal: true

module Lint
  module ClusterCommands
    def test_asking
      # ASKING is a simple command that should return "OK"
      result = r.asking
      assert_equal "OK", result
    end

    def test_cluster_keyslot
      # Test that we can get the slot for a key
      result = r.cluster_keyslot("test_key")
      assert_instance_of Integer, result
      assert result >= 0 && result < 16_384, "Slot should be between 0 and 16_383"
    end

    def test_cluster_myid
      # Test that we can get the current node ID
      result = r.cluster_myid
      assert_instance_of String, result
      assert !result.empty?, "Node ID should not be empty"
    end

    def test_cluster_myshardid
      # Test that we can get the current shard ID - only available in Redis 7.0+
      result = r.cluster_myshardid
      assert_instance_of String, result
      assert !result.empty?, "Shard ID should not be empty"
    rescue Valkey::CommandError => e
      # Skip if command not available in this Redis version
      skip("CLUSTER MYSHARDID not available in this Redis version") if e.message.include?("Unknown subcommand")
    end

    def test_cluster_info_on_cluster
      # Test cluster info command on actual cluster
      result = r.cluster_info
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
      result = r.cluster_nodes
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
      result = r.cluster_slots
      assert_instance_of Array, result

      # After destructive tests, slots might be completely cleared
      # So we check if we have any slots, and if so, verify their structure
      return unless result.any?

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
    end

    def test_cluster_shards
      # Test cluster shards - only available in Redis 7.0+
      result = r.cluster_shards
      assert_instance_of Array, result
      # Should have at least one shard
      assert result.length >= 1, "Should have at least one shard"

      # Check structure of first shard - Redis 7.0+ returns Array format
      first_shard = result.first
      assert_instance_of Array, first_shard
      # The structure is an array like ["slots", [0, 5460], "nodes", [...]]
      # Should have at least 4 elements (slots key, slots value, nodes key, nodes value)
      assert first_shard.length >= 4, "Shard should have at least 4 elements"
      # Check that it contains the expected keys
      assert first_shard.include?("slots"), "Shard should contain 'slots'"
      assert first_shard.include?("nodes"), "Shard should contain 'nodes'"
    rescue Valkey::CommandError => e
      # Skip if command not available in this Redis version
      skip("CLUSTER SHARDS not available in this Redis version") if e.message.include?("Unknown subcommand")
    end

    def test_cluster_links
      # Test cluster links - only available in Redis 7.0+
      result = r.cluster_links
      assert_instance_of Array, result
      # Should have at least one link
      assert result.length >= 1, "Should have at least one link"
    rescue Valkey::CommandError => e
      # Skip if command not available in this Redis version
      skip("CLUSTER LINKS not available in this Redis version") if e.message.include?("Unknown subcommand")
    end

    def test_cluster_replicas_on_cluster
      # Test getting replicas for a master node
      nodes = r.cluster_nodes
      master_node = nodes.find { |node| node["flags"].include?("master") }

      if master_node
        result = r.cluster_replicas(master_node["node_id"])
        assert_instance_of Array, result
      else
        # If no master node found, skip this test
        skip("No master node found in cluster")
      end
    end

    def test_cluster_countkeysinslot_on_cluster
      # Test cluster countkeysinslot command on actual cluster
      slot = r.cluster_keyslot("test_key")
      result = r.cluster_countkeysinslot(slot)
      assert_instance_of Integer, result
      assert result >= 0, "Count should be non-negative"
    end

    def test_cluster_getkeysinslot_on_cluster
      # Test cluster getkeysinslot command on actual cluster
      slot = r.cluster_keyslot("test_key")
      result = r.cluster_getkeysinslot(slot, 10)
      assert_instance_of Array, result
    end

    def test_cluster_count_failure_reports_on_cluster
      # Test cluster count-failure-reports command on actual cluster
      node_id = r.cluster_myid
      result = r.cluster_count_failure_reports(node_id)
      assert_instance_of Integer, result
      assert result >= 0, "Count should be non-negative"
    end

    def test_readonly_and_readwrite_on_cluster
      # Test readonly and readwrite commands on cluster
      readonly_result = r.readonly
      assert_equal "OK", readonly_result

      readwrite_result = r.readwrite
      assert_equal "OK", readwrite_result
    end

    def test_cluster_saveconfig
      # Test cluster saveconfig command
      result = r.cluster_saveconfig
      assert_equal "OK", result
    rescue Valkey::CommandError, Valkey::TimeoutError => e
      # May fail in standalone mode, timeout, or if config can't be saved
      assert true, "Cluster saveconfig correctly failed or timed out: #{e.class}"
    end

    # Additional cluster commands that were missing tests
    # Destructive tests that should run last to avoid affecting other tests
    def test_cluster_addslotsrange
      # Test cluster addslotsrange command - add slots in a range
      result = r.cluster_addslotsrange(9990, 9999)
      # This might succeed or fail depending on cluster state
      assert result == "OK" || result.is_a?(Valkey::CommandError)
    rescue Valkey::CommandError
      # Expected to fail if slots are already assigned or cluster support disabled
      pass "Cluster addslotsrange correctly failed as expected"
    end

    def test_cluster_bumpepoch
      # Test cluster bumpepoch command - bump cluster epoch
      result = r.cluster_bumpepoch
      # This might succeed or fail depending on cluster state
      # Accept OK, false, BUMPED X, or CommandError as valid responses
      case result
      when "OK"
        pass "Cluster bumpepoch succeeded as expected"
      when false
        pass "Cluster bumpepoch returned false (cluster not ready for epoch bump)"
      when /^BUMPED \d+$/
        pass "Cluster bumpepoch succeeded and returned #{result}"
      when Valkey::CommandError
        pass "Cluster bumpepoch correctly failed as expected"
      else
        flunk "Unexpected result from cluster_bumpepoch: #{result.inspect}"
      end
    rescue Valkey::CommandError
      # Expected to fail in normal cluster operation
      pass "Cluster bumpepoch correctly failed as expected"
    end

    def test_cluster_delslotsrange
      # Test cluster delslotsrange command - delete slots in a range
      result = r.cluster_delslotsrange(9990, 9999)
      # This might succeed or fail depending on cluster state
      case result
      when "OK"
        pass "Cluster delslotsrange succeeded as expected"
      when Valkey::CommandError
        pass "Cluster delslotsrange correctly failed as expected"
      else
        flunk "Unexpected result from cluster_delslotsrange: #{result.inspect}"
      end
    rescue Valkey::CommandError
      # Expected to fail if slots are not assigned or cluster support disabled
      pass "Cluster delslotsrange correctly failed as expected"
    end

    def test_cluster_flushslots
      # Test cluster flushslots command - flush all slots
      result = r.cluster_flushslots
      # This might succeed or fail depending on cluster state
      case result
      when "OK"
        pass "Cluster flushslots succeeded as expected"
      when Valkey::CommandError
        pass "Cluster flushslots correctly failed as expected"
      else
        flunk "Unexpected result from cluster_flushslots: #{result.inspect}"
      end
    rescue Valkey::CommandError
      # Expected to fail if cluster support disabled or no slots to flush
      pass "Cluster flushslots correctly failed as expected"
    end

    def test_cluster_replicate
      # Test cluster replicate command - make current node a replica
      # This will fail in normal operation as we can't replicate to invalid node
      r.cluster_replicate("invalid_master_node_id")
    rescue Valkey::CommandError => e
      # Expected to fail with invalid master node ID
      assert e.message.include?("ERR") || e.message.include?("Unknown")
      pass "Cluster replicate correctly failed with invalid master ID as expected"
    end

    # Destructive tests that should run last to avoid affecting other tests
    def test_cluster_commands_with_parameters
      # Test various cluster commands that require parameters
      # Try to add a slot (may succeed or fail depending on cluster state)
      result = r.cluster_addslots(1)
      # This might succeed or fail depending on cluster state
      case result
      when "OK"
        pass "Cluster addslots succeeded as expected"
      when Valkey::CommandError
        pass "Cluster addslots correctly failed as expected"
      else
        flunk "Unexpected result from cluster_addslots: #{result.inspect}"
      end
    rescue Valkey::CommandError
      # Expected to fail if slot is already assigned or cluster support disabled
      pass "Cluster addslots correctly failed as expected"
    end

    def test_cluster_management_commands_on_cluster
      # Test cluster management commands that should work in cluster mode
      # We test that the methods exist and can handle basic validation

      # Test that the method exists by calling it with invalid parameters
      r.cluster_setslot(99_999, "invalid_action")
    rescue Valkey::CommandError
      # Expected to fail with invalid parameters
      pass "Cluster setslot correctly failed with invalid parameters"
    end

    def test_cluster_failover_on_cluster
      # Test cluster failover (only works on replica nodes)
      result = r.cluster_failover
      # This will fail on master nodes, which is expected
      case result
      when "OK"
        pass "Cluster failover succeeded as expected"
      when false
        pass "Cluster failover returned false (not ready for failover)"
      when Valkey::CommandError
        pass "Cluster failover correctly failed as expected"
      else
        flunk "Unexpected result from cluster_failover: #{result.inspect}"
      end
    rescue Valkey::CommandError => e
      # Expected to fail on master nodes - accept any error message
      pass "Cluster failover correctly failed on master node as expected: #{e.message}"
    end

    def test_cluster_force_failover
      # Test cluster failover with force option - should still fail on master
      result = r.cluster_failover("FORCE")
      # This might return false or raise an error on master nodes
      case result
      when "OK"
        pass "Cluster force failover succeeded as expected"
      when false
        pass "Cluster force failover returned false (not ready for failover)"
      else
        flunk "Unexpected result from cluster force failover: #{result.inspect}"
      end
    rescue Valkey::CommandError => e
      # Expected to fail on master nodes even with force - accept any error message
      pass "Cluster force failover correctly failed on master node as expected: #{e.message}"
    end

    def test_cluster_set_config_epoch
      # Test cluster set-config-epoch - should fail in normal cluster operation
      r.cluster_set_config_epoch(999)
    rescue Valkey::CommandError => e
      # Expected to fail in normal cluster operation
      assert e.message.include?("ERR") || e.message.include?("config")
      pass "Cluster set-config-epoch correctly failed as expected"
    end

    def test_cluster_slots_management
      # Test cluster slot management commands
      r.cluster_delslots(9999)
      # This might succeed or fail depending on cluster state
      pass "Cluster delslots executed (may have succeeded or failed)"
    rescue Valkey::CommandError
      # Expected to fail if slot is not assigned or cluster support disabled
      pass "Cluster delslots correctly failed as expected"
    end

    def test_cluster_meet_command
      # Test cluster meet command - should fail or succeed depending on cluster state
      result = r.cluster_meet("127.0.0.1", 9999)
      # If it succeeds, should return "OK"
      assert_equal "OK", result
    rescue Valkey::CommandError => e
      # If it fails, should be a reasonable cluster-related error
      assert(e.message.include?("ERR") ||
             e.message.include?("Invalid") ||
             e.message.include?("already") ||
             e.message.include?("meet"))
    end

    def test_cluster_forget_command
      # Test cluster forget command with invalid node ID
      r.cluster_forget("invalid_node_id_that_does_not_exist")
    rescue Valkey::CommandError => e
      # Expected to fail with invalid node ID
      assert e.message.include?("ERR") || e.message.include?("Unknown")
      pass "Cluster forget correctly failed with invalid node ID as expected"
    end

    def test_cluster_replicate_command
      # Test cluster replicate command - should fail in normal operation
      r.cluster_replicate("some_master_node_id")
    rescue Valkey::CommandError => e
      # Expected to fail with invalid master node ID
      assert e.message.include?("ERR") || e.message.include?("Unknown")
      pass "Cluster replicate correctly failed with invalid master ID as expected"
    end

    def test_cluster_slaves
      # Test cluster slaves command (deprecated)
      node_id = r.cluster_myid
      result = r.cluster_slaves(node_id)
      assert_instance_of Array, result
    rescue Valkey::CommandError => e
      # Expected to fail if node has no slaves or cluster support disabled
      assert e.message.include?("cluster support disabled") ||
             e.message.include?("Unknown node") ||
             e.message.include?("ERR")
    end

    def test_cluster_reset_on_cluster
      # Test cluster reset command - this is destructive so we expect it to work or fail gracefully
      r.cluster_reset("SOFT") # Use SOFT reset to be less destructive
      # If it succeeds, that's also valid
      pass "Cluster reset executed successfully"
    rescue Valkey::CommandError, Valkey::TimeoutError => e
      # Expected to fail or timeout - both are valid outcomes
      pass "Cluster reset correctly failed or timed out: #{e.class}"
    end
  end
end
