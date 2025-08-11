# frozen_string_literal: true

require "test_helper"

class TestClusterCommandsOnClusters < Minitest::Test
  include Helper::Cluster
  # include Lint::StringCommands # Run string tests first (while cluster is healthy)
  include Lint::ClusterCommands # Run cluster commands second (after string tests)
end
