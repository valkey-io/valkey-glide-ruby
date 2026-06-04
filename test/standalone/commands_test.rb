# frozen_string_literal: true

require "test_helper"

# Standalone test class for all Lint command modules
# Runs redis-rb compatibility tests against a standalone Valkey server
class TestStandaloneCommands < Minitest::Test
  include Helper::Client

  # Lint modules for redis-rb compatibility
  include Lint::BitmapCommands
  include Lint::ConnectionCommands
  include Lint::ConnectionOptions
  include Lint::FunctionCommands
  include Lint::GenericCommands
  include Lint::GeoCommands
  include Lint::HashCommands
  include Lint::HyperLogLog
  include Lint::JsonCommands
  include Lint::Lists
  include Lint::ModuleCommands
  include Lint::PubSubCommands
  include Lint::ScriptingCommands
  include Lint::ServerCommands
  include Lint::SetCommands
  include Lint::SortedSetCommands
  include Lint::StreamCommands
  include Lint::StringCommands
  include Lint::TransactionCommands
  include Lint::VectorSearchCommands

  # Note: Lint::ClusterCommands is excluded - only for cluster mode
end
