# frozen_string_literal: true

require "test_helper"

class ErrorMappingTest < Minitest::Test
  def test_maps_server_codes_like_redis_rb
    {
      "NOSCRIPT No matching script." => Valkey::NoScriptError,
      "WRONGTYPE Operation against a key" => Valkey::WrongTypeError,
      "OOM command not allowed" => Valkey::OutOfMemoryError,
      "NOPERM this user has no permissions" => Valkey::PermissionError,
      "READONLY You can't write against a read only replica." => Valkey::ReadOnlyError,
      "MASTERDOWN Link with MASTER is down" => Valkey::ConnectionError,
      "WRONGPASS invalid username-password pair" => Valkey::CannotConnectError,
      "ERR unknown command" => Valkey::CommandError
    }.each do |message, klass|
      error = Valkey.error_for(message)

      assert_instance_of klass, error, message
      assert_equal message, error.message
    end
  end

  def test_restores_server_text_from_glide_extension_errors
    error = Valkey.error_for("WRONGTYPE: Operation against a key holding the wrong kind of value")

    assert_instance_of Valkey::WrongTypeError, error
    assert_equal "WRONGTYPE Operation against a key holding the wrong kind of value", error.message
  end

  def test_restores_server_text_from_glide_kind_names
    {
      "NoScriptError" => ["NOSCRIPT", Valkey::NoScriptError],
      "PermissionDenied" => ["NOPERM", Valkey::PermissionError],
      "ReadOnly" => ["READONLY", Valkey::ReadOnlyError],
      "MasterDown" => ["MASTERDOWN", Valkey::ConnectionError],
      "ResponseError" => ["ERR", Valkey::CommandError],
      "BusyLoadingError" => ["LOADING", Valkey::CommandError]
    }.each do |kind, (code, klass)|
      error = Valkey.error_for("An error was signalled by the server: - #{kind}: some detail")

      assert_instance_of klass, error, kind
      assert_equal "#{code} some detail", error.message
    end
  end

  def test_glide_kind_without_detail
    error = Valkey.error_for("An error was signalled by the server:- NoScriptError")

    assert_instance_of Valkey::NoScriptError, error
    assert_equal "NOSCRIPT", error.message
  end

  def test_leaves_other_messages_untouched
    message = "Received error for address `127.0.0.1:6380`: something"

    assert_equal message, Valkey.error_for(message).message
  end

  def test_maps_error_code_nested_in_script_errors
    message = "ERR Error running script (call to f_abc): @user_script:1: -WRONGTYPE Operation against a key"

    assert_instance_of Valkey::WrongTypeError, Valkey.error_for(message)
  end

  def test_maps_execabort
    assert_instance_of Valkey::ExecAbortError,
                       Valkey.error_for("EXECABORT Transaction discarded because of previous errors.")
  end

  def test_only_server_replies_are_marked
    assert_kind_of Valkey::ServerReply, Valkey.error_for("READONLY You can't write against a read only replica.")
    refute_kind_of Valkey::ServerReply, Valkey::ConnectionError.new("connection dropped")
  end

  def test_reply_blocks_skip_every_error_class
    errors = [
      Valkey.error_for("READONLY nope"),
      Valkey.error_for("MASTERDOWN nope"),
      Valkey.error_for("WRONGPASS nope"),
      Valkey.error_for("ERR nope")
    ]
    blocks = Array.new(errors.size + 1, Valkey::Utils::Boolify)

    results = Valkey.allocate.send(:apply_reply_blocks, [*errors, 1], blocks)

    assert_equal errors, results.first(errors.size)
    assert_equal true, results.last
  end

  def test_reconvert_queued_replies_skips_every_error_class
    errors = [Valkey.error_for("READONLY nope"), Valkey.error_for("MASTERDOWN nope")]
    queued = errors.map { [Valkey::RequestType::EXPIRE, %w[k 1], nil] }

    results = Valkey.allocate.send(:reconvert_queued_replies, errors, queued)

    assert_equal errors, results
  end

  def test_exec_returns_server_replies_that_map_to_connection_errors
    client = multi_client { raise Valkey.error_for("READONLY You can't write against a read only replica.") }

    assert_instance_of Valkey::ReadOnlyError, client.exec.first
  end

  def test_exec_does_not_swallow_transport_failures
    client = multi_client { raise Valkey::ConnectionError, "connection dropped" }

    assert_raises(Valkey::ConnectionError) { client.exec }
  end

  def test_discard_swallows_server_replies_but_not_transport_failures
    assert_nil multi_client { raise Valkey.error_for("MASTERDOWN Link with MASTER is down") }.discard
    assert_raises(Valkey::ConnectionError) { multi_client { raise Valkey::ConnectionError, "dropped" }.discard }
  end

  def test_error_for_uses_the_default_class_for_unrecognised_codes
    assert_instance_of Valkey::ExecAbortError, Valkey.error_for("reworded by glide-core", default: Valkey::ExecAbortError)
    assert_instance_of Valkey::CommandError, Valkey.error_for("reworded by glide-core")
  end

  def test_internal_helpers_are_not_public
    refute_respond_to Valkey, :normalize_server_error
    refute_respond_to Valkey, :server_error_code
    assert_raises(NameError) { Valkey::SERVER_ERROR_CLASSES }
    assert_raises(NameError) { Valkey::GLIDE_ERROR_KIND_CODES }
  end

  def test_watch_unwatches_after_a_server_reply_that_maps_to_a_connection_error
    calls = []
    client = watch_client(calls)

    assert_raises(Valkey::ConnectionError) do
      client.watch("key") { raise Valkey.error_for("MASTERDOWN Link with MASTER is down") }
    end
    assert_includes calls, Valkey::RequestType::UNWATCH
  end

  def test_watch_skips_unwatch_after_a_transport_failure
    calls = []
    client = watch_client(calls)

    assert_raises(Valkey::ConnectionError) do
      client.watch("key") { raise Valkey::ConnectionError, "connection dropped" }
    end
    refute_includes calls, Valkey::RequestType::UNWATCH
  end

  private

  def watch_client(calls)
    client = Valkey.allocate
    client.define_singleton_method(:send_command) do |request_type, *_args, **_opts, &_block|
      calls << request_type
      "OK"
    end
    client
  end

  def multi_client(&failure)
    client = Valkey.allocate
    client.instance_variable_set(:@in_multi, true)
    client.instance_variable_set(:@queued_commands, [])
    client.define_singleton_method(:send_command) { |*_args, **_opts, &_block| failure.call }
    client
  end
end
