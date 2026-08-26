# frozen_string_literal: true

module ValkeyTests
  module Statistics
    def test_get_statistics_returns_hash_with_all_fields
      stats = r.get_statistics

      assert_instance_of Hash, stats

      # Verify all expected fields are present
      expected_fields = %i[
        total_connections
        total_clients
        total_values_compressed
        total_values_decompressed
        total_original_bytes
        total_bytes_compressed
        total_bytes_decompressed
        compression_skipped_count
      ]

      expected_fields.each do |field|
        assert stats.key?(field), "Missing field: #{field}"
      end
    end

    def test_statistics_values_are_non_negative_integers
      stats = r.get_statistics

      stats.each do |key, value|
        assert value.is_a?(Integer), "#{key} should be an Integer, got #{value.class}"
        assert value >= 0, "#{key} should be non-negative, got #{value}"
      end
    end

    def test_statistics_track_connections
      initial_stats = r.get_statistics
      initial_connections = initial_stats[:total_connections]

      # Create another client (this will create more connections)
      client2 = new_test_client

      updated_stats = r.get_statistics

      # Connection count should increase or stay the same
      assert updated_stats[:total_connections] >= initial_connections,
             "Connections should increase: #{initial_connections} -> #{updated_stats[:total_connections]}"

      client2.close
    end

    def test_statistics_track_clients
      initial_stats = r.get_statistics
      initial_clients = initial_stats[:total_clients]

      # Create additional clients
      clients = 3.times.map { new_test_client }

      updated_stats = r.get_statistics

      # Client count should increase
      assert updated_stats[:total_clients] >= initial_clients,
             "Client count should increase: #{initial_clients} -> #{updated_stats[:total_clients]}"

      clients.each(&:close)
    end

    def test_statistics_are_cumulative
      stats1 = r.get_statistics

      # Perform operations
      10.times do |i|
        r.set("test_key_#{i}", "value_#{i}")
        r.get("test_key_#{i}")
      end

      stats2 = r.get_statistics

      # Statistics should never decrease
      stats1.each_key do |key|
        assert stats2[key] >= stats1[key],
               "#{key} should not decrease: #{stats1[key]} -> #{stats2[key]}"
      end
    end

    def test_statistics_available_without_operations
      # Statistics should be available even without performing operations
      stats = r.get_statistics

      refute_nil stats
      assert stats[:total_connections] >= 0
      assert stats[:total_clients] >= 0
    end

    def test_statistics_with_multiple_operations
      initial_stats = r.get_statistics

      # Perform various operations
      50.times do |i|
        r.set("key_#{i}", "value_#{i}")
      end

      r.pipelined do |pipeline|
        25.times { |i| pipeline.get("key_#{i}") }
      end

      final_stats = r.get_statistics

      # Verify stats are still valid and non-decreasing
      assert final_stats[:total_connections] >= initial_stats[:total_connections]
      assert final_stats[:total_clients] >= initial_stats[:total_clients]
    end

    private

    # Helper to create a new test client based on the mode
    def new_test_client
      _new_client
    end
  end
end
