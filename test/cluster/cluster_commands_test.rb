# frozen_string_literal: true

require "test_helper"

class TestClusterCommandsOnClusters < Minitest::Test
  include Helper::Cluster
  include Lint::ClusterCommands  # Run cluster tests first (non-destructive)
  include Lint::StringCommands   # Run string tests last (after cluster is broken)
end
