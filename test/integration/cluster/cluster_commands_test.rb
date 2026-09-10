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
  # TODO: https://github.com/valkey-io/valkey-glide-ruby/issues/135
  # include Lint::PubSubCommands
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
  include ValkeyTests::Call
  include ValkeyTests::ClientInfoTag
  include ValkeyTests::GenericCommands
  include ValkeyTests::Scanning
  include ValkeyTests::ScriptingCommands
  include ValkeyTests::ScriptingCommandsIntegration
  include ValkeyTests::Sorting
  include ValkeyTests::Statistics
  include ValkeyTests::URIConnection

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

# ValkeyTests modules with setup/teardown
class TestClusterFunctionCommands < Minitest::Test
  include Helper::Cluster
  include ValkeyTests::FunctionCommands
end

# Cluster variant of the fork-safety suite (issue #255). Own class so the forked
# child inherits as little minitest state as possible. Note the child MUST exit
# with exit! (Helper::Fork enforces this): Helper::Cluster holds a TestCluster
# whose ObjectSpace finalizer would otherwise run in the child and stop the very
# cluster the parent suite is using.
class TestClusterForkSafety < Minitest::Test
  include Helper::Cluster
  include ValkeyTests::ForkSafety
end

# JSON and MODULE command support is not yet added. Re-enable when implemented.
# TODO: https://github.com/valkey-io/valkey-glide-ruby/issues/233
#
# The lint files are still required by test_helper, so they stay syntax-checked
# and ready to re-enable alongside the lib includes. Note these also require the
# modules to be loaded on all cluster nodes:
#
#   class TestClusterJsonCommands < Minitest::Test
#     include Helper::Cluster
#     include Lint::JsonCommands
#   end
#
#   class TestClusterModuleCommands < Minitest::Test
#     include Helper::Cluster
#     include Lint::ModuleCommands
#   end

# Search (FT.*) in cluster mode is NOT enabled, and this is a measured server
# limitation rather than a client gap. Verified against Valkey 9.1.1 with
# valkey-search 1.2.1 (module ver 66049) on a 3-primary cluster:
#
#   * Index definitions are per-node. ft_create/ft_drop_index now broadcast to
#     all primaries (see Route.all_primaries in vector_search_commands.rb), so
#     index creation/removal works cluster-wide. That half is fixed client-side.
#   * Result aggregation across shards is absent. Documents distribute by slot
#     (6 seeded docs indexed 1/3/2 across three nodes), and a query returns only
#     the shard-local matches: FT.SEARCH ... ALLSHARDS run on the node holding a
#     single document returned exactly that one document, not all six. The
#     ALLSHARDS / SOMESHARDS flags are accepted but do not fan out on this
#     version, so multi-shard result completeness cannot be achieved from the
#     client.
#
# Enabling the class below therefore yields 8 failing result-completeness tests
# (of 29) that no client change can fix. Re-enable once the module supports
# cross-shard aggregation. To reproduce the measurement:
#
#   env -u CLUSTER_ENDPOINTS CLUSTER_MODULES=/abs/path/libsearch.dylib \
#     bundle exec ruby -Itest -Ilib test/integration/cluster/cluster_commands_test.rb \
#       -n '/TestClusterVectorSearchCommands/'
#
#   class TestClusterVectorSearchCommands < Minitest::Test
#     include Helper::Cluster
#     include Lint::VectorSearchCommands
#   end
