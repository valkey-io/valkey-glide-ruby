# frozen_string_literal: true

require "test_helper"

class TestStringCommandsOnClusters < Minitest::Test
  include Helper::Cluster
  include Lint::StringCommands  # Run string tests first (while cluster is healthy)
end 