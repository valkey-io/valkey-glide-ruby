# frozen_string_literal: true

require "test_helper"

class TestIamAuthConfig < Minitest::Test
  def test_elasticache_configuration
    config = Valkey::IamAuthConfig.new(
      cluster_name: "my-cluster",
      service: Valkey::ServiceType::ELASTICACHE,
      region: "us-east-1"
    )

    assert_equal "my-cluster", config.cluster_name
    assert_equal Valkey::ServiceType::ELASTICACHE, config.service
    assert_equal "us-east-1", config.region
    assert_nil config.refresh_interval_seconds
  end

  def test_memorydb_configuration
    config = Valkey::IamAuthConfig.new(
      cluster_name: "my-cluster",
      service: Valkey::ServiceType::MEMORYDB,
      region: "us-west-2"
    )

    assert_equal Valkey::ServiceType::MEMORYDB, config.service
    assert_equal "us-west-2", config.region
  end

  def test_custom_refresh_interval
    config = Valkey::IamAuthConfig.new(
      cluster_name: "my-cluster",
      service: Valkey::ServiceType::ELASTICACHE,
      region: "us-east-1",
      refresh_interval_seconds: 600
    )

    assert_equal 600, config.refresh_interval_seconds
  end
end
