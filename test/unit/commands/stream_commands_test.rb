# frozen_string_literal: true

require "test_helper"

# Unit tests for StreamCommands#xpending argument construction. These stub
# `send_command` on an unconnected client -- see `unconnected_client` below
# (same technique as test/unit/commands/generic_commands_test.rb) -- so they
# run without a server. The end-to-end pass-through lives in
# test/lint/stream_commands.rb, exercised against a real server via
# test/integration/standalone/commands_test.rb and
# test/integration/cluster/cluster_commands_test.rb.
class TestStreamCommandsUnit < Minitest::Test
  def setup
    @valkey = unconnected_client
  end

  def teardown
    @valkey.close
  end

  # should build "key group start end count" in order when idle is not given
  def test_xpending_without_idle_omits_idle
    args = capture_xpending_args("mystream", "mygroup", "-", "+", 10)
    assert_equal ["mystream", "mygroup", "-", "+", 10], args
  end

  # should place "IDLE ms" immediately after key/group, before start/end/count
  # -- the bug in #270/#241 was appending it after those args instead
  def test_xpending_with_idle_places_it_before_start_end_count
    args = capture_xpending_args("mystream", "mygroup", "-", "+", 10, idle: 100)
    assert_equal ["mystream", "mygroup", "IDLE", "100", "-", "+", 10], args
  end

  # should emit "IDLE 0" rather than treating 0 as falsy and omitting it
  def test_xpending_with_idle_zero_still_emits_idle
    args = capture_xpending_args("mystream", "mygroup", "-", "+", 10, idle: 0)
    assert_equal ["mystream", "mygroup", "IDLE", "0", "-", "+", 10], args
  end

  # should only omit IDLE when idle is nil -- a false value should still be
  # forwarded (as "IDLE false") and left for the server to reject, rather
  # than being silently dropped like a real no-filter call
  def test_xpending_with_idle_false_still_emits_idle
    args = capture_xpending_args("mystream", "mygroup", "-", "+", 10, idle: false)
    assert_equal ["mystream", "mygroup", "IDLE", "false", "-", "+", 10], args
  end

  # should not emit IDLE for the summary form (no start/end/count given)
  def test_xpending_summary_without_idle_omits_idle
    args = capture_xpending_args("mystream", "mygroup")
    assert_equal %w[mystream mygroup], args
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

  # Replace the send_command method used by xpending() with a stub which
  # captures the arguments and returns an empty reply, without dispatching
  # to the server.
  def capture_xpending_args(*args, **kwargs)
    captured = nil
    stub = lambda do |_request_type, sent_args = [], &block|
      captured = sent_args
      block ? block.call([]) : []
    end
    @valkey.stub(:send_command, stub) { @valkey.xpending(*args, **kwargs) }
    captured
  end
end
