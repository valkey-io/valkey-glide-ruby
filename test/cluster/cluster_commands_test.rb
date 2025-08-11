# frozen_string_literal: true

require "test_helper"

class TestClusterCommandsOnClusters < Minitest::Test
  include Helper::Cluster
  include Lint::ClusterCommands # Run cluster commands second (after string tests)
end
