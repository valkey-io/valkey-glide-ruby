# frozen_string_literal: true

require "test_helper"

# Unit tests for GenericCommands#call / #call_v argument construction
# (flattening order, flag emission, coercion). These stub `send_command` on
# an unconnected client -- see `unconnected_client` below -- so they run
# without a server. The E2E round-trip tests that prove the whole pipeline
# (construct -> dispatch -> reply) actually works live in
# test/integration/valkey/call_test.rb.
class TestGenericCommandsUnit < Minitest::Test
  def setup
    @valkey = unconnected_client
  end

  def teardown
    @valkey.close
  end

  # should pass args through unchanged when they are already flat strings
  def test_call_arg_construction_passthrough
    assert_equal %w[SET k v], capture_call_args("SET", "k", "v")
  end

  # should stringify Integer/Float args without flattening them
  def test_call_arg_construction_stringifies_integers_and_floats
    assert_equal %w[SET k 42], capture_call_args("SET", "k", 42)
    assert_equal %w[SET k 3.5], capture_call_args("SET", "k", 3.5)
  end

  # should flatten a single Array arg into its own separate elements, in order
  def test_call_arg_construction_flattens_array
    assert_equal %w[LPUSH list 1 2 3], capture_call_args("LPUSH", "list", [1, 2, 3])
  end

  # should recursively flatten nested Arrays, not just one level deep
  def test_call_arg_construction_flattens_nested_array
    assert_equal %w[LPUSH list 1 2 3 4], capture_call_args("LPUSH", "list", [1, [2, [3, 4]]])
  end

  # should flatten a Hash arg to alternating key/value strings, preserving pair order
  def test_call_arg_construction_flattens_hash
    assert_equal %w[HMSET hash foo 1 bar 2], capture_call_args("HMSET", "hash", { "foo" => 1, "bar" => 2 })
  end

  # should flatten a Hash whose values are Arrays (key preserved, value flattened)
  def test_call_arg_construction_flattens_hash_with_array_values
    assert_equal %w[CMD k foo 1 2], capture_call_args("CMD", "k", { "foo" => [1, 2] })
  end

  # should apply the same flattening to call_v's single Array argument,
  # including a Hash value that is itself an Array (mirrors
  # test_call_arg_construction_flattens_hash_with_array_values for call)
  def test_call_v_arg_construction_flattens
    assert_equal %w[LPUSH list 1 2 3], capture_call_v_args(["LPUSH", "list", [1, 2, 3]])
    assert_equal %w[CMD k foo 1 2], capture_call_v_args(["CMD", "k", { "foo" => [1, 2] }])
  end

  # should append upcased flag names for truthy boolean kwargs, in the order given
  def test_call_arg_construction_boolean_flags
    assert_equal %w[SET k v NX], capture_call_args("SET", "k", "v", nx: true)
  end

  # should append both the upcased flag name and its stringified value for
  # non-boolean truthy kwargs
  def test_call_arg_construction_value_flags
    assert_equal %w[SET k v EX 60], capture_call_args("SET", "k", "v", ex: 60)
  end

  # should drop false-valued and nil-valued kwargs entirely, not stringify them
  def test_call_arg_construction_drops_falsy_and_nil_flags
    assert_equal %w[SET k v], capture_call_args("SET", "k", "v", nx: false, ex: nil)
  end

  # should combine positional flattening and trailing flags in a single call,
  # flags always appended after all positional (including flattened) args
  def test_call_arg_construction_combines_flattening_and_flags
    assert_equal %w[SET k v NX EX 60], capture_call_args("SET", "k", "v", nx: true, ex: 60)
  end

  private

  # Builds a `Valkey` client while stubbing the FFI call that would normally
  # open a real connection (same technique as `captured_client_args` in
  # test/unit/connection_config_test.rb), then clears `@connection` so
  # `#close` in teardown is a no-op instead of reaching real FFI.
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

  # Replaces send_command with a stub that captures the args call() built,
  # without dispatching to the server.
  def capture_call_args(*args, **kwargs)
    captured = nil
    stub = lambda do |_request_type, sent_args = [], **_opts, &_block|
      captured = sent_args
      "OK"
    end
    @valkey.stub(:send_command, stub) { @valkey.call(*args, **kwargs) }
    captured
  end

  def capture_call_v_args(args)
    captured = nil
    stub = lambda do |_request_type, sent_args = [], **_opts, &_block|
      captured = sent_args
      "OK"
    end
    @valkey.stub(:send_command, stub) { @valkey.call_v(args) }
    captured
  end
end
