# frozen_string_literal: true

require "test_helper"

# Standalone test class for valkey-glide-ruby specific tests
# Runs ValkeyTests modules against a standalone Valkey server
class TestStandaloneValkey < Minitest::Test
  include Helper::Client

  # ValkeyTests modules for valkey-glide-ruby specific functionality
  include ValkeyTests::Bitpos
  include ValkeyTests::FunctionCommands
  include ValkeyTests::GenericCommands
  include ValkeyTests::OpenTelemetry
  include ValkeyTests::Scanning
  include ValkeyTests::ScriptingCommands
  include ValkeyTests::ScriptingCommandsIntegration
  include ValkeyTests::Sorting
  include ValkeyTests::Statistics
  include ValkeyTests::URIConnection
  include ValkeyTests::Utils

  # Property-based test modules for eval/evalsha
  include ValkeyTests::EvalEvalshaBasicProperties
  include ValkeyTests::EvalEvalshaValidationProperties
  include ValkeyTests::EvalEvalshaTypeProperties
end
