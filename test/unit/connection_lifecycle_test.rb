# frozen_string_literal: true

require "test_helper"
require "timeout"

# Unit test for Valkey#close's use of Mutex#try_lock to guard against a
# double-free of the native handle. No real connection is involved -- the
# client's ivars are set directly via Valkey.allocate -- so this runs
# without a server, unlike its sibling lifecycle tests in
# test/integration/valkey/connection_lifecycle_test.rb.
class TestConnectionLifecycleUnit < Minitest::Test
  # Direct regression for the interleaving that motivated the try_lock:
  # a TracePoint pauses the first thread's `close` between the ivar read
  # and the ivar clear, lets a second thread run `close` to completion,
  # then releases the first. Without the lock, both threads free the same
  # handle; with `Mutex#try_lock` in `close`, only one thread does.
  # Reproducer contributed by @nderraugh on PR #224.
  def test_concurrent_close_releases_native_handle_once_traced
    client = Valkey.allocate
    pointer = FFI::Pointer.new(1)
    client.instance_variable_set(:@connection, pointer)
    client.instance_variable_set(:@close_lock, Mutex.new)

    source_path, source_line = Valkey.instance_method(:close).source_location
    # Line of `@connection = nil` inside the `begin` block. Locate it
    # dynamically so a future refactor of `close` cannot silently
    # invalidate the pause point.
    lines = File.readlines(source_path)
    pause_line = (source_line..(source_line + 30)).find do |ln|
      lines[ln - 1]&.strip == "@connection = nil"
    end
    refute_nil pause_line, "could not locate `@connection = nil` inside close"

    reached_pause = Queue.new
    release_first_close = Queue.new
    close_calls = []
    first_close = nil

    trace = TracePoint.new(:line) do |event|
      next unless Thread.current[:first_close]
      next unless event.path == source_path && event.lineno == pause_line

      # A :line event fires before the line executes. At this point the
      # first close has copied @connection into conn but has not cleared
      # @connection.
      reached_pause << true
      release_first_close.pop
    end

    Valkey::Bindings.stub(:close_client, ->(conn) { close_calls << conn }) do
      trace.enable
      first_close = Thread.new do
        Thread.current[:first_close] = true
        client.close
      end

      Timeout.timeout(2) { reached_pause.pop }

      # The second close attempts to capture and release the same pointer
      # while the first close is paused. With try_lock, it short-circuits.
      Thread.new { client.close }.join
    ensure
      release_first_close << true
      first_close&.join
      trace.disable
    end

    assert_equal 1, close_calls.size,
                 "close_client should be invoked exactly once for one native ownership count"
    assert_same pointer, close_calls.first
  end
end
