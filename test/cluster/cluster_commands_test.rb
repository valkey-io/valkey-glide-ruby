# frozen_string_literal: true

require "test_helper"

# Cluster test class for command modules WITHOUT custom setup methods
# These modules can safely share a test class
class TestClusterCommands < Minitest::Test
  include Helper::Cluster

  # Lint modules without conflicting setup methods
  include Lint::BitmapCommands
  include Lint::ConnectionCommands
  include Lint::ConnectionOptions
  include Lint::FunctionCommands
  include Lint::GenericCommands
  include Lint::HashCommands
  include Lint::HyperLogLog
  include Lint::Lists
  include Lint::PubSubCommands
  include Lint::ScriptingCommands
  include Lint::ServerCommands
  include Lint::SetCommands
  include Lint::SortedSetCommands
  include Lint::StreamCommands
  include Lint::StringCommands
  include Lint::TransactionCommands

  # Cluster-specific commands
  include Lint::ClusterCommands

  # ValkeyTests modules without conflicting setup methods
  include ValkeyTests::Bitpos
  include ValkeyTests::ConnectionConfig
  include ValkeyTests::Call
  include ValkeyTests::GenericCommands
  include ValkeyTests::Scanning
  include ValkeyTests::ScriptingCommands
  include ValkeyTests::ScriptingCommandsIntegration
  include ValkeyTests::Sorting
  include ValkeyTests::Statistics
  include ValkeyTests::URIConnection
  include ValkeyTests::Utils

  # Eval/Evalsha property tests
  include ValkeyTests::EvalEvalshaBasicProperties
  include ValkeyTests::EvalEvalshaValidationProperties
  include ValkeyTests::EvalEvalshaTypeProperties
end

# Modules WITH custom setup methods need their own test class
# to avoid setup interference between different command groups

class TestClusterGeoCommands < Minitest::Test
  include Helper::Cluster
  include Lint::GeoCommands
end

class TestClusterJsonCommands < Minitest::Test
  include Helper::Cluster
  include Lint::JsonCommands
end

class TestClusterModuleCommands < Minitest::Test
  include Helper::Cluster
  include Lint::ModuleCommands
end

class TestClusterVectorSearchCommands < Minitest::Test
  include Helper::Cluster
  include Lint::VectorSearchCommands
end

# ValkeyTests modules with setup/teardown
class TestClusterFunctionCommands < Minitest::Test
  include Helper::Cluster
  include ValkeyTests::FunctionCommands
end

# NOTE: Module tests (JsonCommands, ModuleCommands, VectorSearchCommands)
# require modules loaded on all cluster nodes
