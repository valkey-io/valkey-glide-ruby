# frozen_string_literal: true

require "test_helper"

class TestClusterCommandsOnClusters < Minitest::Test
  include Helper::Cluster

  # ========================================
  # Lint Modules (redis-rb compatibility)
  # ========================================

  # String commands - uses {1} hash tags for multi-key ops
  include Lint::StringCommands

  # Hash commands work in cluster mode
  include Lint::HashCommands

  # List commands - uses {1} hash tags for multi-key ops
  include Lint::Lists

  # Set commands - uses {1} hash tags for multi-key ops
  include Lint::SetCommands

  # Sorted set commands - most tests use single keys or hash tags
  include Lint::SortedSetCommands

  # Stream commands work in cluster mode
  include Lint::StreamCommands

  # Generic commands - uses {key} hash tags for multi-key ops
  include Lint::GenericCommands

  # Bitmap commands - uses {1} hash tags for multi-key ops
  include Lint::BitmapCommands

  # Geo commands - single key operations
  include Lint::GeoCommands

  # HyperLogLog commands - uses {1} hash tags for multi-key ops
  include Lint::HyperLogLog

  # Scripting commands work per-node
  include Lint::ScriptingCommands

  # Server commands work in cluster mode (per-node)
  include Lint::ServerCommands

  # Connection commands (cluster-aware)
  include Lint::ConnectionCommands

  # Connection options work in cluster mode
  include Lint::ConnectionOptions

  # Pub/Sub works in cluster mode
  include Lint::PubSubCommands

  # Function commands work in cluster mode (per-node)
  include Lint::FunctionCommands

  # Module commands work in cluster mode (per-node)
  include Lint::ModuleCommands

  # JSON commands work in cluster mode (requires module on all nodes)
  include Lint::JsonCommands

  # Cluster-specific commands
  include Lint::ClusterCommands

  # ========================================
  # ValkeyTests Modules (valkey-glide-ruby specific)
  # ========================================

  # Generic commands tests - compatible with cluster mode
  include ValkeyTests::GenericCommands

  # Statistics tests - has cluster_mode? aware helper
  include ValkeyTests::Statistics

  # OpenTelemetry tests - has skip if cluster_mode? in all tests
  include ValkeyTests::OpenTelemetry

  # URI connection tests - has skip if cluster_mode? in all tests
  include ValkeyTests::URIConnection

  # Sorting tests - single key operations
  include ValkeyTests::Sorting

  # Bitpos tests - single key operations
  include ValkeyTests::Bitpos

  # Utils tests - pure utility tests, no server connection needed
  include ValkeyTests::Utils

  # Scanning tests - all tests are commented out, safe to include
  include ValkeyTests::Scanning

  # Function commands setup/teardown - compatible with cluster mode
  include ValkeyTests::FunctionCommands

  # Scripting commands - works per-node
  include ValkeyTests::ScriptingCommands
  include ValkeyTests::ScriptingCommandsIntegration

  # Eval/Evalsha property tests - works per-node
  include ValkeyTests::EvalEvalshaBasicProperties
  include ValkeyTests::EvalEvalshaValidationProperties
  include ValkeyTests::EvalEvalshaTypeProperties
end

# NOTE: Module tests (JsonCommands, ModuleCommands) require modules loaded on all cluster nodes
