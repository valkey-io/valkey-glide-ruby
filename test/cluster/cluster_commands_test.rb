# frozen_string_literal: true

require "test_helper"

class TestClusterCommandsOnClusters < Minitest::Test
  include Helper::Cluster
  # include Lint::StringCommands # Run string tests first (while cluster is healthy)
  include Lint::HashCommands # Hash commands work in cluster mode
  include Lint::ConnectionCommands # Run connection tests (cluster-aware)
  include Lint::PubSubCommands # Pub/Sub works in cluster mode
  include Lint::FunctionCommands # Function commands work in cluster mode (per-node)
  include Lint::ModuleCommands # Module commands work in cluster mode (per-node)
  include Lint::ClusterCommands # Run cluster commands second (after string tests)
end
