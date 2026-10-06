# frozen_string_literal: true

require "test_helper"

# Verifies that cluster seed validation still permits a real cluster connection.
class TestClusterSeedValidationIntegration < Minitest::Test
  include Helper::Cluster

  def test_cluster_client_connects_with_explicit_seed
    seed = Helper::Cluster.cluster_addresses.first
    client = Valkey.new(nodes: [seed], cluster_mode: true, timeout: TIMEOUT)

    assert_equal "PONG", client.ping
  ensure
    client&.close
  end
end
