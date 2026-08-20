# frozen_string_literal: true

require "test_helper"

# Unit tests for ServerCommands#failover argument construction. These stub
# `send_command` on an unconnected client -- see `unconnected_client` below
# (same technique as test/unit/commands/generic_commands_test.rb) -- so they
# run without a server. The end-to-end failover behavior lives in
# test/integration/valkey/failover_commands_test.rb, which needs a real
# standalone primary/replica pair.
class TestServerCommandsUnit < Minitest::Test
  def setup
    @valkey = unconnected_client
  end

  def teardown
    @valkey.close
  end

  # should send "ABORT" only
  def test_failover_abort_sends_abort_only
    assert_equal ["ABORT"], capture_failover_args(abort: true, timeout: 5000)
  end

  # should not send "FORCE" unless a TO target is supplied
  def test_failover_force_without_target_omits_force
    assert_equal [], capture_failover_args(force: true)
  end

  # should build "TO host port FORCE TIMEOUT ms" in order for a full request
  def test_failover_builds_full_arg_list_in_order
    args = capture_failover_args(to: "127.0.0.1 6380", force: true, timeout: 5000)
    assert_equal ["TO", "127.0.0.1", "6380", "FORCE", "TIMEOUT", "5000"], args
  end

  private

  def unconnected_client(options = {})
    fake_response = Valkey::Bindings::ConnectionResponse.new
    fake_response[:conn_ptr] = FFI::Pointer.new(0x1)

    client = nil
    stub_create = ->(_uri, _json, _client_type, _callback) { fake_response.to_ptr }
    Valkey::Bindings.stub(:create_client_from_uri, stub_create) do
      Valkey::Bindings.stub(:free_connection_response, nil) do
        client = ::Valkey.new({ host: "localhost", port: 6379 }.merge(options))
      end
    end
    client.instance_variable_set(:@connection, nil)
    client
  end

  # Replace the send_command method used by failover() with a stub which
  # captures the arguments and returns "OK", without dispatching to the
  # server.
  def capture_failover_args(**options)
    captured = nil
    stub = lambda do |_request_type, args = [], &_block|
      captured = args
      "OK"
    end
    @valkey.stub(:send_command, stub) { @valkey.failover(**options) }
    captured
  end
end
