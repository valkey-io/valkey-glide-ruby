# frozen_string_literal: true

require "test_helper"

# Server-free unit tests for the fork-safety guard (issue #255).
#
#   parent_proc  the process that created the client (`@pid == Process.pid`)
#   child_proc   a process that inherited it across fork() (`@pid != Process.pid`)
#
# These never fork; the roles are modelled by the recorded pid, which is all the
# guard compares. Real fork coverage is in
# test/integration/valkey/fork_safety_test.rb.
class TestForkSafety < Minitest::Test
  # Raised by the FFI stubs below, so a test can tell "the guard refused" apart
  # from "the guard let us reach the native layer".
  class FfiReached < StandardError; end

  def other_proc_pid
    Process.pid + 1
  end

  def parent_proc_client(connection: FFI::Pointer.new(1))
    build_client(pid: Process.pid, connection: connection)
  end

  def child_proc_client(connection: FFI::Pointer.new(1))
    build_client(pid: other_proc_pid, connection: connection)
  end

  def unowned_client(connection: FFI::Pointer.new(1))
    build_client(pid: :unset, connection: connection)
  end

  def build_client(pid:, connection:)
    client = Valkey.allocate
    client.instance_variable_set(:@connection, connection)
    client.instance_variable_set(:@close_lock, Mutex.new)
    client.instance_variable_set(:@pid, pid) unless pid == :unset
    client.instance_variable_set(:@in_multi, false)
    client.instance_variable_set(:@queued_commands, [])
    client
  end

  def test_initialize_stamps_the_parent_proc_pid
    fake_response = Valkey::Bindings::ConnectionResponse.new
    fake_response[:conn_ptr] = FFI::Pointer.new(0x1)

    client = nil
    Valkey::Bindings.stub(:create_client_from_uri, ->(_uri, _json, _type, _cb) { fake_response.to_ptr }) do
      Valkey::Bindings.stub(:free_connection_response, nil) do
        client = Valkey.new(host: "localhost", port: 6379)
      end
    end
    # Drop the fake handle so nothing can later try to free it natively.
    client.instance_variable_set(:@connection, nil)

    assert_equal Process.pid, client.instance_variable_get(:@pid)
  end

  def test_connection_in_child_proc_raises_inherited_error
    client = child_proc_client

    error = assert_raises(Valkey::InheritedError) { client.send(:connection!) }

    assert_equal "Cannot use a client created before fork(). " \
                 "Create a new client in the child process.", error.message

    # Asserted through a real rescue clause, not `assert_kind_of`: the class
    # hierarchy is true with no guard implemented, a caught raise is not.
    caught = begin
      client.send(:connection!)
    rescue Valkey::BaseConnectionError => e
      e
    end

    assert_instance_of Valkey::InheritedError, caught
  end

  def test_connection_in_parent_proc_returns_the_handle_unchanged
    pointer = FFI::Pointer.new(1)
    client = parent_proc_client(connection: pointer)

    assert_same pointer, client.send(:connection!)
  end

  # The pid check runs before the closed check, so an inherited client reports
  # the fork rather than sending the user looking for a stray `close`.
  def test_child_proc_check_takes_precedence_over_the_closed_check
    client = child_proc_client(connection: nil)

    error = assert_raises(Valkey::InheritedError) { client.send(:connection!) }

    refute_instance_of Valkey::ConnectionError, error
  end

  def test_closed_client_in_parent_proc_still_raises_connection_error
    client = parent_proc_client(connection: nil)

    error = assert_raises(Valkey::ConnectionError) { client.send(:connection!) }

    assert_equal "the client is closed", error.message
  end

  def test_null_connection_in_parent_proc_still_raises_connection_error
    client = parent_proc_client(connection: FFI::Pointer::NULL)

    assert_raises(Valkey::ConnectionError) { client.send(:connection!) }
  end

  def test_send_command_in_child_proc_raises_inherited_error_before_reaching_ffi
    client = child_proc_client
    ffi_calls = []

    Valkey::Bindings.stub(:command, lambda { |*args|
      ffi_calls << args
      raise FfiReached
    }) do
      assert_raises(Valkey::InheritedError) do
        client.send_command(Valkey::RequestType::GET, ["foo"])
      end
    end

    assert_empty ffi_calls
  end

  def test_send_batch_commands_in_child_proc_raises_inherited_error_before_reaching_ffi
    client = child_proc_client
    ffi_calls = []

    Valkey::Bindings.stub(:batch, lambda { |*args|
      ffi_calls << args
      raise FfiReached
    }) do
      assert_raises(Valkey::InheritedError) do
        client.send(:send_batch_commands, [[Valkey::RequestType::GET, ["foo"], nil]])
      end
    end

    assert_empty ffi_calls
  end

  def test_invoke_script_in_child_proc_raises_inherited_error_before_reaching_ffi
    client = child_proc_client
    ffi_calls = []

    Valkey::Bindings.stub(:invoke_script, lambda { |*args|
      ffi_calls << args
      raise FfiReached
    }) do
      assert_raises(Valkey::InheritedError) do
        client.invoke_script("a" * 40, keys: ["foo"], args: ["bar"])
      end
    end

    assert_empty ffi_calls
  end

  # Pins the decision from the other side: statistics takes no handle, so a
  # guard bolted onto every public method instead of onto `connection!` would
  # break this.
  def test_statistics_in_child_proc_is_not_guarded_because_it_takes_no_handle
    client = child_proc_client
    stats = { total_connections: 1, total_clients: 1, total_values_compressed: 0,
              total_values_decompressed: 0, total_original_bytes: 0, total_bytes_compressed: 0,
              total_bytes_decompressed: 0, compression_skipped_count: 0 }

    Valkey::Bindings.stub(:get_statistics, stats) do
      assert_equal 1, client.statistics[:total_connections]
    end
  end

  def test_close_in_child_proc_does_not_free_the_native_handle
    client = child_proc_client
    close_calls = []

    Valkey::Bindings.stub(:close_client, ->(conn) { close_calls << conn }) do
      client.close
    end

    assert_empty close_calls
  end

  # Ordering constraint: the pid `return` sits after `@connection = nil`, so a
  # child that ignores the error gets ConnectionError rather than a live pointer
  # into a dead runtime. Guarding the whole method would break this.
  def test_close_in_child_proc_still_clears_the_connection
    client = child_proc_client

    Valkey::Bindings.stub(:close_client, ->(_conn) {}) do
      client.close
    end

    assert_nil client.instance_variable_get(:@connection)
  end

  # Regression guard for #212 / #224.
  def test_close_in_parent_proc_frees_the_native_handle_exactly_once
    pointer = FFI::Pointer.new(1)
    client = parent_proc_client(connection: pointer)
    close_calls = []

    Valkey::Bindings.stub(:close_client, ->(conn) { close_calls << conn }) do
      client.close
      client.close
    end

    assert_equal [pointer], close_calls
  end

  # The guard is `@pid != Process.pid`, not `@pid && @pid != Process.pid`: the
  # failure modes are asymmetric. Skipping a free on a handle we cannot prove we
  # own leaks one handle; freeing one we do not own kills the process.
  def test_close_with_no_recorded_proc_does_not_free_the_native_handle
    client = unowned_client
    close_calls = []

    Valkey::Bindings.stub(:close_client, ->(conn) { close_calls << conn }) do
      client.close
    end

    assert_empty close_calls
    assert_nil client.instance_variable_get(:@connection)
  end

  # `disconnect!` is an alias, so it inherits the guard. Pinned in case it is
  # ever reimplemented as its own method.
  def test_disconnect_in_child_proc_does_not_free_the_native_handle
    client = child_proc_client
    close_calls = []

    Valkey::Bindings.stub(:close_client, ->(conn) { close_calls << conn }) do
      client.disconnect!
    end

    assert_empty close_calls
    assert_nil client.instance_variable_get(:@connection)
  end

  def test_close_is_idempotent_in_child_proc
    client = child_proc_client
    close_calls = []

    Valkey::Bindings.stub(:close_client, ->(conn) { close_calls << conn }) do
      client.close
      client.close
    end

    assert_empty close_calls
  end
end
