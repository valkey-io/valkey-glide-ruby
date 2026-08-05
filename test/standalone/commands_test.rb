# frozen_string_literal: true

require "test_helper"

# Standalone test class for command modules WITHOUT custom setup methods
# These modules can safely share a test class
class TestStandaloneCommands < Minitest::Test
  include Helper::Client

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

  # NOTE: Lint::ClusterCommands is excluded - only for cluster mode
end

# Modules WITH custom setup methods need their own test class
# to avoid setup interference between different command groups

class TestStandaloneGeoCommands < Minitest::Test
  include Helper::Client
  include Lint::GeoCommands
end

# Server-modules support is not yet added. Re-enable when implemented.
# TODO: https://github.com/valkey-io/valkey-glide-ruby/issues/233
#       https://github.com/valkey-io/valkey-glide-ruby/issues/234
#
# The lint files are still required by test_helper, so they stay syntax-checked
# and ready to re-enable alongside the lib includes:
#
#   class TestStandaloneJsonCommands < Minitest::Test
#     include Helper::Client
#     include Lint::JsonCommands
#   end
#
#   class TestStandaloneModuleCommands < Minitest::Test
#     include Helper::Client
#     include Lint::ModuleCommands
#   end
#
#   class TestStandaloneVectorSearchCommands < Minitest::Test
#     include Helper::Client
#     include Lint::VectorSearchCommands
#   end
