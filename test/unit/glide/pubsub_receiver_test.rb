# frozen_string_literal: true

require "test_helper"
require "timeout"

# Unit tests for Valkey::Glide::PubSubReceiver: queue mode, callback mode, and
# the `pubsub:` option keys that configure them.
class TestPubSubReceiverUnit < Minitest::Test
  Kind = Valkey::Commands::PubSubCommands::PushKind

  def teardown
    @receiver&.close
  end

  # --- Queue mode ----------------------------------------------------------

  def test_queue_mode_delivers_messages_in_delivery_order
    @receiver = Valkey::Glide::PubSubReceiver.new

    push(Kind::MESSAGE, message: "exact", channel: "news")
    push(Kind::PMESSAGE, message: "pattern", channel: "news.tech", pattern: "news.*")
    push(Kind::SMESSAGE, message: "sharded", channel: "shard-chan")

    expected = [
      ["exact", "news", nil],
      ["pattern", "news.tech", "news.*"],
      ["sharded", "shard-chan", nil]
    ]

    received = 3.times.map { @receiver.try_pop.to_a }

    assert_equal expected, received
  end

  def test_try_pop_returns_nil_when_the_queue_is_empty
    @receiver = Valkey::Glide::PubSubReceiver.new

    assert_nil @receiver.try_pop
  end

  def test_close_wakes_a_blocked_pop_with_nil
    @receiver = Valkey::Glide::PubSubReceiver.new

    reader = Thread.new { @receiver.pop }
    # Let the reader reach the blocking pop before the queue closes.
    sleep 0.05
    @receiver.close

    assert_nil Timeout.timeout(2) { reader.value }
  end

  def test_queue_mode_is_not_callback_mode
    @receiver = Valkey::Glide::PubSubReceiver.new

    refute_predicate @receiver, :callback_mode?
  end

  # --- Callback mode -------------------------------------------------------

  def test_callback_mode_is_reported
    @receiver = Valkey::Glide::PubSubReceiver.new(callback: ->(_message, _context) {})

    assert_predicate @receiver, :callback_mode?
  end

  def test_callback_receives_messages_in_delivery_order
    received = Thread::Queue.new
    @receiver = Valkey::Glide::PubSubReceiver.new(callback: ->(message, _context) { received.push(message) })

    push(Kind::MESSAGE, message: "exact", channel: "news")
    push(Kind::PMESSAGE, message: "pattern", channel: "news.tech", pattern: "news.*")

    expected = [
      ["exact", "news", nil],
      ["pattern", "news.tech", "news.*"]
    ]

    delivered = 2.times.map { received.pop.to_a }

    assert_equal expected, delivered
  end

  def test_callback_mode_leaves_the_queue_empty
    @receiver = Valkey::Glide::PubSubReceiver.new(callback: ->(_message, _context) {})

    push(Kind::MESSAGE, message: "exact", channel: "news")

    assert_empty @receiver.instance_variable_get(:@message_queue)
  end

  def test_callback_of_arity_one_receives_only_the_message
    received = Thread::Queue.new
    @receiver = Valkey::Glide::PubSubReceiver.new(
      callback: ->(message) { received.push([message]) },
      context: :ignored
    )

    push(Kind::MESSAGE, message: "exact", channel: "news")

    arguments = received.pop

    assert_equal 1, arguments.size
    assert_equal "exact", arguments.first.message
  end

  def test_callback_of_arity_two_receives_the_context
    received = Thread::Queue.new
    context = { state: "app" }
    @receiver = Valkey::Glide::PubSubReceiver.new(
      callback: ->(message, callback_context) { received.push([message, callback_context]) },
      context: context
    )

    push(Kind::MESSAGE, message: "exact", channel: "news")

    message, delivered_context = received.pop

    assert_equal "exact", message.message
    assert_same context, delivered_context
  end

  # A non-lambda proc has lenient arity (-1), so the single `arity == 1` rule
  # sends it the context too.
  def test_non_lambda_proc_receives_the_context
    received = Thread::Queue.new
    callback = proc { |message, callback_context| received.push([message, callback_context]) }
    @receiver = Valkey::Glide::PubSubReceiver.new(callback: callback, context: :app_state)

    push(Kind::MESSAGE, message: "exact", channel: "news")

    message, delivered_context = received.pop

    assert_equal "exact", message.message
    assert_equal :app_state, delivered_context
  end

  def test_raising_callback_does_not_propagate_and_does_not_kill_the_receiver
    received = Thread::Queue.new
    callback = lambda do |message, _context|
      raise "callback boom" if message.message == "first"

      received.push(message)
    end
    @receiver = Valkey::Glide::PubSubReceiver.new(callback: callback)

    push(Kind::MESSAGE, message: "first", channel: "news")
    push(Kind::MESSAGE, message: "second", channel: "news")

    assert_equal "second", received.pop.message
    assert_empty received
  end

  def test_pop_raises_in_callback_mode
    @receiver = Valkey::Glide::PubSubReceiver.new(callback: ->(_message, _context) {})

    error = assert_raises(Valkey::CommandError) { Timeout.timeout(2) { @receiver.pop } }

    assert_match(%r{Inline Pub/Sub reads are unavailable}, error.message)
  end

  def test_try_pop_raises_in_callback_mode
    @receiver = Valkey::Glide::PubSubReceiver.new(callback: ->(_message, _context) {})

    error = assert_raises(Valkey::CommandError) { @receiver.try_pop }

    assert_match(%r{Inline Pub/Sub reads are unavailable}, error.message)
  end

  # --- FFI push handler ----------------------------------------------------

  def test_ffi_handler_is_the_same_object_on_every_read
    @receiver = Valkey::Glide::PubSubReceiver.new

    assert_same @receiver.ffi_handler, @receiver.ffi_handler
  end

  def test_ffi_handler_drops_non_message_kinds_in_callback_mode
    received = Thread::Queue.new
    @receiver = Valkey::Glide::PubSubReceiver.new(callback: ->(message, _context) { received.push(message) })

    non_message_kinds = [
      Kind::DISCONNECTION, Kind::OTHER, Kind::INVALIDATE,
      Kind::SUBSCRIBE, Kind::PSUBSCRIBE, Kind::SSUBSCRIBE,
      Kind::UNSUBSCRIBE, Kind::PUNSUBSCRIBE, Kind::SUNSUBSCRIBE
    ]

    non_message_kinds.each do |kind|
      push(kind, message: "phantom", channel: "news")

      assert_empty received, "kind #{kind} must not reach the callback"
    end
  end

  def test_ffi_handler_preserves_an_embedded_nul_in_callback_mode
    payload = "before\0after"
    received = Thread::Queue.new
    @receiver = Valkey::Glide::PubSubReceiver.new(callback: ->(message, _context) { received.push(message) })

    push(Kind::MESSAGE, message: payload, channel: "news")

    assert_equal payload, received.pop.message
  end

  # --- `pubsub:` option ----------------------------------------------------

  def test_context_without_callback_raises
    error = assert_raises(ArgumentError) { Valkey.new(pubsub: { context: :app_state }) }

    assert_equal "Pub/Sub context: requires a callback:", error.message
  end

  def test_non_callable_callback_raises
    error = assert_raises(ArgumentError) { Valkey.new(pubsub: { callback: "not callable" }) }

    assert_equal "Pub/Sub callback: must respond to #call, got: String", error.message
  end

  def test_callback_and_context_build_a_callback_mode_receiver
    received = Thread::Queue.new
    pubsub_configs = {
      subscriptions: { exact: ["news"] },
      callback: ->(message, callback_context) { received.push([message, callback_context]) },
      context: :app_state
    }

    @receiver = build_pubsub_receiver(pubsub_configs)

    push(Kind::MESSAGE, message: "exact", channel: "news")

    message, delivered_context = received.pop

    assert_predicate @receiver, :callback_mode?
    assert_equal "exact", message.message
    assert_equal :app_state, delivered_context
  end

  def test_callback_and_context_stay_out_of_the_connection_json
    pubsub_configs = {
      subscriptions: { exact: ["news"] },
      callback: ->(_message, _context) {},
      context: :app_state
    }

    parsed = Valkey.allocate.send(:parse_pubsub_configs, pubsub_configs, protocol: :resp3)

    assert_equal({ "pubsub_subscriptions" => { "0" => ["news"] } }, parsed)
  end

  def test_omitted_callback_builds_a_queue_mode_receiver
    @receiver = build_pubsub_receiver(subscriptions: { exact: ["news"] })

    refute_predicate @receiver, :callback_mode?

    push(Kind::MESSAGE, message: "exact", channel: "news")

    assert_equal "exact", @receiver.try_pop.message
  end

  private

  # Reflection because the builder is private on the client, and `allocate`
  # because it needs neither a connection nor the rest of `initialize`.
  def build_pubsub_receiver(pubsub_configs)
    Valkey.allocate.send(:build_pubsub_receiver, pubsub_configs)
  end

  # Calls the retained FFI handler the way the Rust push worker does, with real
  # buffers and the byte lengths alongside them.
  def push(kind, message: nil, channel: nil, pattern: nil)
    message_pointer, message_length = buffer_for(message)
    channel_pointer, channel_length = buffer_for(channel)
    pattern_pointer, pattern_length = buffer_for(pattern)

    @receiver.ffi_handler.call(
      0, kind,
      message_pointer, message_length,
      channel_pointer, channel_length,
      pattern_pointer, pattern_length
    )
  end

  def buffer_for(value)
    return [FFI::Pointer::NULL, 0] if value.nil?

    bytes = value.b
    buffer = FFI::MemoryPointer.new(:char, bytes.bytesize)
    buffer.put_bytes(0, bytes)
    [buffer, bytes.bytesize]
  end
end
