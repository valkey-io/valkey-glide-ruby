# frozen_string_literal: true

require "test_helper"

# Standalone test class for valkey-glide-ruby specific tests
# Runs ValkeyTests modules against a standalone Valkey server
class TestStandaloneValkey < Minitest::Test
  include Helper::Client

  # ValkeyTests modules for valkey-glide-ruby specific functionality
  include ValkeyTests::AuthCommands
  include ValkeyTests::Bitpos
  include ValkeyTests::Call
  include ValkeyTests::ClientInfoTag
  include ValkeyTests::ConnectionLifecycle
  include ValkeyTests::FailoverCommands
  include ValkeyTests::FunctionCommands
  include ValkeyTests::GenericCommands
  include ValkeyTests::Scanning
  include ValkeyTests::ScriptingCommands
  include ValkeyTests::ScriptingCommandsIntegration
  include ValkeyTests::Sorting
  include ValkeyTests::Statistics
  include ValkeyTests::URIConnection
  include ValkeyTests::FlattenMap

  # Property-based test modules for eval/evalsha
  include ValkeyTests::EvalEvalshaBasicProperties
  include ValkeyTests::EvalEvalshaValidationProperties
  include ValkeyTests::EvalEvalshaTypeProperties
end

# Fork-safety tests get their own class: they fork the test process, so keeping
# them out of the big shared class limits how much inherited minitest state the
# child carries. See test/support/helper/fork.rb for the exit!/finalizer note.
class TestStandaloneForkSafety < Minitest::Test
  include Helper::Client
  include ValkeyTests::ForkSafety
end

# OpenTelemetry tests need their own class to avoid setup interference
# The OTel module has its own setup that initializes OpenTelemetry once,
# and including Helper::Client would cause extra commands (flushdb) to
# generate spans that interfere with span counting tests.
class TestStandaloneOpenTelemetry < Minitest::Test
  include ValkeyTests::OpenTelemetry

  # OpenTelemetry tests create their own clients internally and don't need
  # the standard Helper::Client setup which would generate extra spans.
  # We just need to provide the cluster_mode? method that the module expects.
  def cluster_mode?
    false
  end
end
