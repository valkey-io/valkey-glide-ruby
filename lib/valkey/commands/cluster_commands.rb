# frozen_string_literal: true

class Valkey
  module Commands
    # This module contains commands related to Redis Cluster management.
    #
    # @see https://valkey.io/commands/#cluster
    #
    module ClusterCommands
      # Send ASKING command to the server.
      #
      # @return [String] `"OK"`
      def asking
        send_command(RequestType::ASKING)
      end

      # Add slots to the cluster.
      #
      # @param [Array<Integer>] slots array of slot numbers
      # @return [String] `"OK"`
      def cluster_addslots(*slots)
        send_command(RequestType::CLUSTER_ADD_SLOTS, slots)
      end

      # Add a range of slots to the cluster.
      #
      # @param [Integer] start_slot starting slot number
      # @param [Integer] end_slot ending slot number
      # @return [String] `"OK"`
      def cluster_addslotsrange(start_slot, end_slot)
        send_command(RequestType::CLUSTER_ADD_SLOTS_RANGE, [start_slot, end_slot])
      end

      # Bump the epoch of the cluster.
      #
      # @return [String] `"OK"`
      def cluster_bumpepoch
        send_command(RequestType::CLUSTER_BUMP_EPOCH)
      end

      # Count failure reports for a node.
      #
      # @param [String] node_id the node ID
      # @return [Integer] number of failure reports
      def cluster_count_failure_reports(node_id)
        send_command(RequestType::CLUSTER_COUNT_FAILURE_REPORTS, [node_id])
      end

      # Count keys in a specific slot.
      #
      # @param [Integer] slot the slot number
      # @return [Integer] number of keys in the slot
      def cluster_countkeysinslot(slot)
        send_command(RequestType::CLUSTER_COUNT_KEYS_IN_SLOT, [slot])
      end

      # Delete slots from the cluster.
      #
      # @param [Array<Integer>] slots array of slot numbers
      # @return [String] `"OK"`
      def cluster_delslots(*slots)
        send_command(RequestType::CLUSTER_DEL_SLOTS, slots)
      end

      # Delete a range of slots from the cluster.
      #
      # @param [Integer] start_slot starting slot number
      # @param [Integer] end_slot ending slot number
      # @return [String] `"OK"`
      def cluster_delslotsrange(start_slot, end_slot)
        send_command(RequestType::CLUSTER_DEL_SLOTS_RANGE, [start_slot, end_slot])
      end

      # Force a failover of the cluster.
      #
      # @param [String] force force the failover
      # @return [String] `"OK"`
      def cluster_failover(force = nil)
        args = []
        args << "FORCE" if force
        send_command(RequestType::CLUSTER_FAILOVER, args)
      end

      # Flush all slots from the cluster.
      #
      # @return [String] `"OK"`
      def cluster_flushslots
        send_command(RequestType::CLUSTER_FLUSH_SLOTS)
      end

      # Remove a node from the cluster.
      #
      # @param [String] node_id the node ID to forget
      # @return [String] `"OK"`
      def cluster_forget(node_id)
        send_command(RequestType::CLUSTER_FORGET, [node_id])
      end

      # Get keys in a specific slot.
      #
      # @param [Integer] slot the slot number
      # @param [Integer] count maximum number of keys to return
      # @return [Array<String>] array of keys
      def cluster_getkeysinslot(slot, count)
        send_command(RequestType::CLUSTER_GET_KEYS_IN_SLOT, [slot, count])
      end

      # Get information about the cluster.
      #
      # @return [Hash<String, String>] cluster information
      def cluster_info
        send_command(RequestType::CLUSTER_INFO) do |reply|
          Utils::HashifyInfo.call(reply)
        end
      end

      # Get the slot for a key.
      #
      # @param [String] key the key name
      # @return [Integer] slot number
      def cluster_keyslot(key)
        send_command(RequestType::CLUSTER_KEY_SLOT, [key])
      end

      # Get information about cluster links.
      #
      # @return [Array<Hash>] array of link information
      def cluster_links
        send_command(RequestType::CLUSTER_LINKS)
      end

      # Meet another node in the cluster.
      #
      # @param [String] ip IP address of the node
      # @param [Integer] port port of the node
      # @return [String] `"OK"`
      def cluster_meet(ip, port)
        send_command(RequestType::CLUSTER_MEET, [ip, port])
      end

      # Get the ID of the current node.
      #
      # @return [String] node ID
      def cluster_myid
        send_command(RequestType::CLUSTER_MY_ID)
      end

      # Get the shard ID of the current node.
      #
      # @return [String] shard ID
      def cluster_myshardid
        send_command(RequestType::CLUSTER_MY_SHARD_ID)
      end

      # Get information about all nodes in the cluster.
      #
      # @return [Array<Hash>] array of node information
      def cluster_nodes
        send_command(RequestType::CLUSTER_NODES) do |reply|
          Utils::HashifyClusterNodes.call(reply)
        end
      end

      # Get information about replica nodes.
      #
      # @param [String] node_id the master node ID
      # @return [Array<Hash>] array of replica information
      def cluster_replicas(node_id)
        send_command(RequestType::CLUSTER_REPLICAS, [node_id]) do |reply|
          Utils::HashifyClusterSlaves.call(reply)
        end
      end

      # Set a node as a replica of another node.
      #
      # @param [String] node_id the master node ID
      # @return [String] `"OK"`
      def cluster_replicate(node_id)
        send_command(RequestType::CLUSTER_REPLICATE, [node_id])
      end

      # Reset the cluster.
      #
      # @param [String] hard hard reset
      # @return [String] `"OK"`
      def cluster_reset(hard = nil)
        args = []
        args << "HARD" if hard
        send_command(RequestType::CLUSTER_RESET, args)
      end

      # Save the cluster configuration.
      #
      # @return [String] `"OK"`
      def cluster_saveconfig
        send_command(RequestType::CLUSTER_SAVE_CONFIG)
      end

      # Set the config epoch for a node.
      #
      # @param [Integer] epoch the config epoch
      # @return [String] `"OK"`
      def cluster_set_config_epoch(epoch)
        send_command(RequestType::CLUSTER_SET_CONFIG_EPOCH, [epoch])
      end

      # Set the state of a slot.
      #
      # @param [Integer] slot the slot number
      # @param [String] state the state (importing, migrating, node, stable)
      # @param [String] node_id the node ID (optional)
      # @return [String] `"OK"`
      def cluster_setslot(slot, state, node_id = nil)
        args = [slot, state]
        args << node_id if node_id
        send_command(RequestType::CLUSTER_SETSLOT, args)
      end

      # Get information about cluster shards.
      #
      # @return [Array<Hash>] array of shard information
      def cluster_shards
        send_command(RequestType::CLUSTER_SHARDS)
      end

      # Get information about slave nodes (deprecated, use cluster_replicas).
      #
      # @return [Array<Hash>] array of slave information
      def cluster_slaves(node_id)
        send_command(RequestType::CLUSTER_SLAVES, [node_id]) do |reply|
          Utils::HashifyClusterSlaves.call(reply)
        end
      end

      # Get information about cluster slots.
      #
      # @return [Array<Hash>] array of slot information
      def cluster_slots
        send_command(RequestType::CLUSTER_SLOTS) do |reply|
          Utils::HashifyClusterSlots.call(reply)
        end
      end

      # Set the connection to read-only mode.
      #
      # @return [String] "OK"
      def readonly
        send_command(RequestType::READ_ONLY)
      end

      # Set the connection to read-write mode.
      #
      # @return [String] "OK"
      def readwrite
        send_command(RequestType::READ_WRITE)
      end
    end
  end
end
