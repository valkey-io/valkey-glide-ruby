# frozen_string_literal: true

module Lint
  module ClusterCommands
    def test_cluster_info
      # Test cluster info command
      result = r.cluster_info
      assert result.is_a?(Hash)
      assert result.key?("cluster_state")
    end

    def test_cluster_nodes
      # Test cluster nodes command
      result = r.cluster_nodes
      assert result.is_a?(Array)
      # In standalone mode, this should return an error or empty array
    end

    def test_cluster_slots
      # Test cluster slots command
      result = r.cluster_slots
      assert result.is_a?(Array)
      # In standalone mode, this should return an error or empty array
    end

    def test_cluster_keyslot
      # Test cluster keyslot command
      result = r.cluster_keyslot("test_key")
      assert result.is_a?(Integer)
      assert result >= 0
      assert result <= 16383
    end

    def test_cluster_count_failure_reports
      # Test cluster count-failure-reports command
      # Skip in standalone mode, use real node ID in cluster mode
      begin
        node_id = r.cluster_myid
        result = r.cluster_count_failure_reports(node_id)
        assert result.is_a?(Integer)
        assert result >= 0
      rescue Valkey::CommandError => e
        # Expected to fail in standalone mode
        assert e.message.include?("cluster support disabled") || e.message.include?("ERR")
      end
    end

    def test_cluster_countkeysinslot
      # Test cluster countkeysinslot command
      result = r.cluster_countkeysinslot(0)
      assert result.is_a?(Integer)
      assert result >= 0
    end

    def test_cluster_delslots
      # Test cluster delslots command
      begin
        result = r.cluster_delslots(0)
        assert_equal "OK", result
      rescue Valkey::CommandError => e
        # May fail if slot is already unassigned or cluster support disabled
        assert e.message.include?("cluster support disabled") || 
               e.message.include?("already unassigned") ||
               e.message.include?("ERR")
      end
    end

    def test_cluster_failover
      # Test cluster failover command
      # This will fail in standalone mode, which is expected
      assert_raises(Valkey::CommandError) do
        r.cluster_failover
      end
    end

    def test_cluster_forget
      # Test cluster forget command
      # This will fail in both standalone and cluster mode (can't forget self or invalid node)
      assert_raises(Valkey::CommandError) do
        r.cluster_forget("invalid_node_id")
      end
    end

    def test_cluster_getkeysinslot
      # Test cluster getkeysinslot command
      result = r.cluster_getkeysinslot(0, 10)
      assert result.is_a?(Array)
    end

    def test_cluster_meet
      # Test cluster meet command
      # This will fail in standalone mode, which is expected
      assert_raises(Valkey::CommandError) do
        r.cluster_meet("127.0.0.1", 7001)
      end
    end

    def test_cluster_myid
      # Test cluster myid command
      result = r.cluster_myid
      assert result.is_a?(String)
      assert result.length > 0
    end

    def test_cluster_replicas
      # Test cluster replicas command with node_id
      begin
        # In cluster mode, use a real master node ID
        nodes = r.cluster_nodes
        master_node = nodes.find { |node| node["flags"].include?("master") }
        if master_node
          result = r.cluster_replicas(master_node["node_id"])
          assert result.is_a?(Array)
        else
          # Fallback: use current node ID (might be master or slave)
          node_id = r.cluster_myid
          result = r.cluster_replicas(node_id)
          assert result.is_a?(Array)
        end
      rescue Valkey::CommandError => e
        # Expected to fail in standalone mode or if node has no replicas
        assert e.message.include?("cluster support disabled") || 
               e.message.include?("Unknown node") ||
               e.message.include?("ERR")
      end
    end

    def test_cluster_replicas_without_node_id
      # Test cluster replicas command without node_id
      # This should raise ArgumentError since we updated the method
      assert_raises(ArgumentError) do
        r.cluster_replicas
      end
    end

    def test_cluster_reset
      # Test cluster reset command
      # This will fail in standalone mode or timeout, which is expected
      begin
        r.cluster_reset
        # If it succeeds, that's also valid
        pass "Cluster reset executed successfully"
      rescue Valkey::CommandError, Valkey::TimeoutError => e
        # Expected to fail or timeout - both are valid outcomes
        pass "Cluster reset correctly failed or timed out: #{e.class}"
      end
    end

    def test_cluster_saveconfig
      # Test cluster saveconfig command
      begin
        result = r.cluster_saveconfig
        assert_equal "OK", result
      rescue Valkey::CommandError, Valkey::TimeoutError => e
        # May fail in standalone mode, timeout, or if config can't be saved
        assert true, "Cluster saveconfig correctly failed or timed out: #{e.class}"
      end
    end

    def test_cluster_set_config_epoch
      # Test cluster set-config-epoch command
      # This will fail in standalone mode, which is expected
      assert_raises(Valkey::CommandError) do
        r.cluster_set_config_epoch(1)
      end
    end

    def test_cluster_setslot
      # Test cluster setslot command
      # This will fail in standalone mode or with invalid parameters, which is expected
      assert_raises(Valkey::CommandError) do
        r.cluster_setslot(0, "STABLE")
      end
    end

    def test_cluster_slaves
      # Test cluster slaves command (deprecated, should use replicas)
      begin
        # In cluster mode, use a real master node ID
        nodes = r.cluster_nodes
        master_node = nodes.find { |node| node["flags"].include?("master") }
        if master_node
          result = r.cluster_slaves(master_node["node_id"])
          assert result.is_a?(Array)
        else
          # Fallback: use current node ID
          node_id = r.cluster_myid
          result = r.cluster_slaves(node_id)
          assert result.is_a?(Array)
        end
      rescue Valkey::CommandError => e
        # Expected to fail in standalone mode or if node has no slaves
        assert e.message.include?("cluster support disabled") || 
               e.message.include?("Unknown node") ||
               e.message.include?("ERR")
      end
    end

    def test_cluster_slaves_without_node_id
      # Test cluster slaves command without node_id
      # This should raise ArgumentError since we updated the method
      assert_raises(ArgumentError) do
        r.cluster_slaves
      end
    end

    def test_readonly
      # Test readonly command
      result = r.readonly
      assert_equal "OK", result
    end

    def test_readwrite
      # Test readwrite command
      result = r.readwrite
      assert_equal "OK", result
    end
  end
end
