# frozen_string_literal: true

require "test_helper"

# Unit tests for mapping server error replies to specific error classes and for
# how pipelines, transactions and WATCH treat those errors versus transport failures.
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
      error = Valkey.make_server_reply_error(message)

      assert_instance_of klass, error, message
      assert_equal message, error.message
    end
  end

  def test_restores_server_text_from_glide_extension_errors
    error = Valkey.make_server_reply_error("WRONGTYPE: Operation against a key holding the wrong kind of value")

    assert_instance_of Valkey::WrongTypeError, error
    assert_equal "WRONGTYPE Operation against a key holding the wrong kind of value", error.message
  end

  def test_restores_server_text_from_glide_kind_names
    {
      "ResponseError" => ["ERR", Valkey::CommandError],
      "ExecAbortError" => ["EXECABORT", Valkey::ExecAbortError],
      "BusyLoadingError" => ["LOADING", Valkey::CommandError],
      "NoScriptError" => ["NOSCRIPT", Valkey::NoScriptError],
      "Moved" => ["MOVED", Valkey::CommandError],
      "Ask" => ["ASK", Valkey::CommandError],
      "TryAgain" => ["TRYAGAIN", Valkey::CommandError],
      "ClusterDown" => ["CLUSTERDOWN", Valkey::CommandError],
      "CrossSlot" => ["CROSSSLOT", Valkey::CommandError],
      "MasterDown" => ["MASTERDOWN", Valkey::ConnectionError],
      "ReadOnly" => ["READONLY", Valkey::ReadOnlyError],
      "NotBusy" => ["NOTBUSY", Valkey::CommandError],
      "PermissionDenied" => ["NOPERM", Valkey::PermissionError]
    }.each do |kind, (code, klass)|
      error = Valkey.make_server_reply_error("An error was signalled by the server: - #{kind}: some detail")

      assert_instance_of klass, error, kind
      assert_equal "#{code} some detail", error.message
    end
  end

  def test_glide_kind_without_detail
    error = Valkey.make_server_reply_error("An error was signalled by the server:- NoScriptError")

    assert_instance_of Valkey::NoScriptError, error
    assert_equal "NOSCRIPT", error.message
  end

  def test_strips_repeated_glide_prefix_from_detail
    error = Valkey.make_server_reply_error(
      "An error was signalled by the server: - ResponseError: An error was signalled by the server: Library not found"
    )

    assert_equal "ERR Library not found", error.message
  end

  def test_glide_kind_with_only_the_repeated_prefix_returns_the_code
    error = Valkey.make_server_reply_error(
      "An error was signalled by the server: - NoScriptError: An error was signalled by the server: "
    )

    assert_equal "NOSCRIPT", error.message
  end

  def test_restores_server_text_from_mixed_case_extension_errors
    error = Valkey.make_server_reply_error("Invalid: query string syntax")

    assert_instance_of Valkey::CommandError, error
    assert_equal "Invalid query string syntax", error.message
  end

  def test_leaves_glide_originated_errors_untouched
    ["PipelineResponseError: slot failed", "IoError: broken pipe"].each do |message|
      assert_equal message, Valkey.make_server_reply_error(message).message
    end
  end

  def test_leaves_other_messages_untouched
    message = "Received error for address `127.0.0.1:6380`: something"

    assert_equal message, Valkey.make_server_reply_error(message).message
  end

  def test_maps_error_code_nested_in_script_errors
    error = Valkey.make_server_reply_error(
      "An error was signalled by the server: - ResponseError: Error running script (call to f_abc): " \
      "@user_script:1: -WRONGTYPE Operation against a key"
    )

    assert_instance_of Valkey::WrongTypeError, error
    assert_equal "ERR Error running script (call to f_abc): @user_script:1: -WRONGTYPE Operation against a key",
                 error.message
  end

  def test_maps_execabort
    assert_instance_of Valkey::ExecAbortError,
                       Valkey.make_server_reply_error("EXECABORT Transaction discarded because of previous errors.")
  end

  def test_reply_blocks_skip_every_error_class
    errors = [
      Valkey.make_server_reply_error("READONLY nope"),
      Valkey.make_server_reply_error("MASTERDOWN nope"),
      Valkey.make_server_reply_error("WRONGPASS nope"),
      Valkey.make_server_reply_error("ERR nope")
    ]
    blocks = Array.new(errors.size + 1, Valkey::Utils::Boolify)

    results = Valkey.allocate.send(:apply_reply_blocks, [*errors, 1], blocks)

    assert_equal errors, results.first(errors.size)
    assert_equal true, results.last
  end

  def test_reconvert_queued_replies_skips_every_error_class
    errors = [Valkey.make_server_reply_error("READONLY nope"), Valkey.make_server_reply_error("MASTERDOWN nope")]
    queued = errors.map { [Valkey::RequestType::EXPIRE, %w[k 1], nil] }

    results = Valkey.allocate.send(:reconvert_queued_replies, errors, queued)

    assert_equal errors, results
  end

  def test_exec_returns_server_replies_that_map_to_connection_errors
    error = Valkey.make_server_reply_error("READONLY You can't write against a read only replica.")
    client = multi_client { raise error }

    assert_instance_of Valkey::ReadOnlyError, client.exec.first
  end

  def test_exec_does_not_swallow_transport_failures
    client = multi_client { raise Valkey::ConnectionError, "connection dropped" }

    assert_raises(Valkey::ConnectionError) { client.exec }
  end

  def test_discard_swallows_server_replies
    assert_nil multi_client { raise Valkey.make_server_reply_error("MASTERDOWN Link with MASTER is down") }.discard
  end

  def test_discard_does_not_swallow_transport_failures
    assert_raises(Valkey::ConnectionError) { multi_client { raise Valkey::ConnectionError, "dropped" }.discard }
  end

  def test_exec_without_multi_returns_nil_on_server_reply
    client = Valkey.allocate
    client.define_singleton_method(:send_command) do |*_args, **_opts, &_block|
      raise Valkey.make_server_reply_error("ERR EXEC without MULTI")
    end

    assert_nil client.exec
  end

  def test_exec_without_multi_does_not_swallow_transport_failures
    client = Valkey.allocate
    client.define_singleton_method(:send_command) do |*_args, **_opts, &_block|
      raise Valkey::ConnectionError, "connection dropped"
    end

    assert_raises(Valkey::ConnectionError) { client.exec }
  end

  def test_make_server_reply_error_uses_the_default_class_for_unrecognised_codes
    error = Valkey.make_server_reply_error("reworded by glide-core", default: Valkey::ExecAbortError)

    assert_instance_of Valkey::ExecAbortError, error
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
      client.watch("key") { raise Valkey.make_server_reply_error("MASTERDOWN Link with MASTER is down") }
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
