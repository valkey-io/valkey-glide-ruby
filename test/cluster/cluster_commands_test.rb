# frozen_string_literal: true

require "test_helper"

class TestClusterCommandsOnClusters < Minitest::Test
  include Helper::Cluster
  include Lint::ClusterCommands

  def test_cluster_info_on_cluster
    # Test cluster info command on actual cluster
    result = valkey.cluster_info
    assert result.is_a?(Hash)
    assert result.key?("cluster_state")
    # In cluster mode, cluster_state should be "ok"
    assert_equal "ok", result["cluster_state"]
  end

  def test_cluster_nodes_on_cluster
    # Test cluster nodes command on actual cluster
    result = valkey.cluster_nodes
    assert result.is_a?(Array)
    # Should have 6 nodes (7001-7006)
    assert result.length >= 6, "Should have at least 6 nodes in cluster"
  end

  def test_cluster_slots_on_cluster
    # Test cluster slots command on actual cluster
    result = valkey.cluster_slots
    assert result.is_a?(Array)
    # Should have slot information for all 16384 slots
    assert result.length > 0, "Should have slot information"
  end

  def test_cluster_myid_on_cluster
    # Test cluster myid command on actual cluster
    result = valkey.cluster_myid
    assert result.is_a?(String)
    assert result.length > 0, "Node ID should not be empty"
  end

  def test_cluster_keyslot_on_cluster
    # Test cluster keyslot command on actual cluster
    result = valkey.cluster_keyslot("test_key")
    assert result.is_a?(Integer)
    assert result >= 0 && result <= 16383, "Slot should be between 0 and 16383"
  end

  def test_cluster_countkeysinslot_on_cluster
    # Test cluster countkeysinslot command on actual cluster
    slot = valkey.cluster_keyslot("test_key")
    result = valkey.cluster_countkeysinslot(slot)
    assert result.is_a?(Integer)
    assert result >= 0, "Key count should be non-negative"
  end

  def test_cluster_getkeysinslot_on_cluster
    # Test cluster getkeysinslot command on actual cluster
    slot = valkey.cluster_keyslot("test_key")
    result = valkey.cluster_getkeysinslot(slot, 10)
    assert result.is_a?(Array)
  end

  def test_cluster_count_failure_reports_on_cluster
    # Test cluster count-failure-reports command on actual cluster
    node_id = valkey.cluster_myid
    result = valkey.cluster_count_failure_reports(node_id)
    assert result.is_a?(Integer)
    assert result >= 0, "Failure report count should be non-negative"
  end

  def test_cluster_replicas_on_cluster
    # Test cluster replicas command on actual cluster
    node_id = valkey.cluster_myid
    result = valkey.cluster_replicas(node_id)
    assert result.is_a?(Array)
  end

  def test_readonly_and_readwrite_on_cluster
    # Test readonly and readwrite commands on cluster
    readonly_result = valkey.readonly
    assert_equal "OK", readonly_result

    readwrite_result = valkey.readwrite
    assert_equal "OK", readwrite_result
  end

  def test_cluster_management_commands_on_cluster
    # Test cluster management commands that should work in cluster mode
    
    # Test cluster failover (should work in cluster mode)
    begin
      result = valkey.cluster_failover
      assert_equal "OK", result
    rescue => e
      # Might fail if not a replica node
      assert e.message.include?("ERR") || e.message.include?("MOVED")
    end

    # Test cluster reset (should work in cluster mode)
    begin
      result = valkey.cluster_reset
      assert_equal "OK", result
    rescue => e
      # Might fail depending on cluster state
      assert e.message.include?("ERR") || e.message.include?("MOVED")
    end
  end
end 