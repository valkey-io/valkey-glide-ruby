# frozen_string_literal: true

require "test_helper"

class TestClusterCommandsOnClusters < Minitest::Test
  include Helper::Cluster
  include Lint::StringCommands # Run string tests first (while cluster is healthy)
  include Lint::ClusterCommands # Run cluster commands second (after string tests)

  # Override the test method to ensure proper ordering
  def self.test_order
    :alpha
  end

  # Ensure string tests run before cluster tests by prefixing them
  def self.test_methods
    methods = super
    # Sort string tests first, then cluster tests
    string_tests = methods.select { |m| m.start_with?('test_') && !m.include?('cluster_') }
    cluster_tests = methods.select { |m| m.start_with?('test_') && m.include?('cluster_') }
    destructive_tests = methods.select { |m| m.start_with?('z_test_') }
    
    string_tests.sort + cluster_tests.sort + destructive_tests.sort
  end
end
