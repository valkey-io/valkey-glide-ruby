# frozen_string_literal: true

require "test_helper"
require "timeout"

# Unit tests for Valkey::Glide::PubSub.
# TODO: https://github.com/valkey-io/valkey-glide-ruby/issues/135.
class TestGlidePubSubUnit < Minitest::Test
  Kind = Valkey::Glide::PubSub::PushKind

  # Stands in for the Valkey client so dispatch can be asserted without a
  # server: records what would have gone over the wire and replies with a
  # canned value.
  class RecordingClient
    SentCommand = Struct.new(:request_type, :args)

    attr_reader :sent_commands

    def initialize(response: nil)
      @sent_commands = []
      @response = response
    end

    def send_command(request_type, args = [], **_options)
      @sent_commands << SentCommand.new(request_type, args)
      @response
    end

    def last_command
      @sent_commands.last
    end
  end

  # Pub/Sub requires RESP3, so the shared instance declares it; the protocol
  # guard itself is exercised with purpose-built instances further down.
  def setup
    @pubsub = Valkey::Glide::PubSub.new(nil, cluster_mode: false, protocol: :resp3)
  end

  def teardown
    @pubsub&.close
  end

  # Enqueues without going through the FFI, so the queue contract can be tested
  # before the handler exists. `deliver` is private because nothing outside the
  # handler may call it in production.
  def deliver(message:, channel:, pattern: nil)
    @pubsub.send(:deliver, Valkey::Glide::PubSub::Message.new(message, channel, pattern))
  end

  def test_message_kinds_cover_only_payload_carrying_pushes
    assert_equal [Kind::MESSAGE, Kind::PMESSAGE, Kind::SMESSAGE], Kind::MESSAGE_KINDS
    refute_includes Kind::MESSAGE_KINDS, Kind::SUBSCRIBE
    refute_includes Kind::MESSAGE_KINDS, Kind::DISCONNECTION
  end

  def test_message_carries_message_channel_and_pattern
    msg = Valkey::Glide::PubSub::Message.new("hello", "news.tech", "news.*")

    assert_equal "hello", msg.message
    assert_equal "news.tech", msg.channel
    assert_equal "news.*", msg.pattern
  end

  # Rust holds the function pointer for the client's lifetime, so the proc has
  # to be the same retained object every time, not a fresh one per call.
  def test_ffi_handler_is_retained
    assert_same @pubsub.ffi_handler, @pubsub.ffi_handler
  end

  def test_try_get_message_returns_nil_when_empty
    assert_nil @pubsub.try_get_message
  end

  def test_get_message_returns_messages_in_delivery_order
    3.times { |i| deliver(message: "m#{i}", channel: "news") }

    received = 3.times.map { @pubsub.get_message.message }

    assert_equal %w[m0 m1 m2], received
  end

  def test_close_wakes_a_blocked_reader_with_nil
    reader = Thread.new { @pubsub.get_message }
    # Let the reader reach the blocking pop before the queue closes.
    sleep 0.05
    @pubsub.close

    assert_nil Timeout.timeout(2) { reader.value }
  end

  def test_try_get_message_returns_nil_once_closed
    @pubsub.close

    assert_nil @pubsub.try_get_message
  end

  # --- Pub/Sub connection options -----------------------------------------

  def test_pubsub_explicit_resp2_raises
    error = assert_raises(Valkey::Resp3RequiredError) do
      Valkey::Glide::PubSub.parse_config({ subscriptions: { exact: ["news"] } }, protocol: :resp2)
    end
    assert_match(/RESP3/, error.message)
  end

  def test_pubsub_omitted_protocol_raises
    error = assert_raises(Valkey::Resp3RequiredError) do
      Valkey::Glide::PubSub.parse_config({ subscriptions: { exact: ["news"] } })
    end
    assert_match(/RESP3/, error.message)
  end

  def test_pubsub_explicit_nil_protocol_raises
    error = assert_raises(Valkey::Resp3RequiredError) do
      Valkey::Glide::PubSub.parse_config({ subscriptions: { exact: ["news"] } }, protocol: nil)
    end
    assert_match(/RESP3/, error.message)
  end

  def test_pubsub_parse_config_ok
    pubsub_config = {
      subscriptions: { exact: ["news", :symbols], pattern: ["news.*"], sharded: ["news.shard"] }
    }

    parsed = Valkey::Glide::PubSub.parse_config(pubsub_config, protocol: :resp3)

    expected = { "pubsub_subscriptions" => { "0" => %w[news symbols], "1" => ["news.*"], "2" => ["news.shard"] } }

    assert_equal expected, parsed
  end

  def test_pubsub_parse_config_nil
    config = Valkey::Glide::PubSub.parse_config(nil)
    expected = Valkey::Glide::PubSub.parse_config({})
    assert_equal config, expected
  end

  def test_pubsub_unknown_subscription_mode_raises
    error = assert_raises(ArgumentError) do
      Valkey::Glide::PubSub.parse_config({ subscriptions: { unknown_mode: ["news.*"] } })
    end

    assert_equal "Unknown Pub/Sub subscription mode(s): unknown_mode. Valid modes are: exact, pattern, sharded",
                 error.message
  end

  # --- FFI push handler ----------------------------------------------------

  def test_ffi_handler_queues_messages
    push(Kind::MESSAGE, message: "exact", channel: "news")
    push(Kind::PMESSAGE, message: "pattern", channel: "news.tech", pattern: "news.*")
    push(Kind::SMESSAGE, message: "sharded", channel: "shard-chan")

    expected = [
      ["exact", "news", nil],
      ["pattern", "news.tech", "news.*"],
      ["sharded", "shard-chan", nil]
    ]

    received = 3.times.map { @pubsub.try_get_message.to_a }

    assert_equal expected, received
  end

  def test_ffi_handler_drops_non_message_kinds
    non_message_kinds = [
      Kind::DISCONNECTION, Kind::OTHER, Kind::INVALIDATE,
      Kind::SUBSCRIBE, Kind::PSUBSCRIBE, Kind::SSUBSCRIBE,
      Kind::UNSUBSCRIBE, Kind::PUNSUBSCRIBE, Kind::SUNSUBSCRIBE
    ]

    non_message_kinds.each do |kind|
      push(kind, message: "phantom", channel: "news")

      assert_nil @pubsub.try_get_message, "kind #{kind} must not queue a message"
    end
  end

  def test_ffi_handler_with_embedded_nul
    payload = "before\0after"

    push(Kind::MESSAGE, message: payload, channel: "news")

    assert_equal payload, @pubsub.try_get_message.message
  end

  # --- Command dispatch ----------------------------------------------------

  def test_subscribe
    client = RecordingClient.new
    pubsub = build_pubsub(client)

    pubsub.subscribe("news", "alerts", timeout: 2000)

    assert_equal Valkey::RequestType::SUBSCRIBE_BLOCKING, client.last_command.request_type
    assert_equal %w[news alerts 2000], client.last_command.args
  end

  def test_subscribe_with_default
    client = RecordingClient.new
    build_pubsub(client).subscribe("news")

    assert_equal %w[news 0], client.last_command.args
  end

  def test_subscribe_fractional_milliseconds
    client = RecordingClient.new
    pubsub = build_pubsub(client)

    pubsub.subscribe("news", timeout: 1500.6)
    pubsub.subscribe("news", timeout: 250.2)

    assert_equal %w[news 1500], client.sent_commands[0].args
    assert_equal %w[news 250], client.sent_commands[1].args
  end

  def test_subscribe_sub_milliseconds_timeout
    client = RecordingClient.new

    build_pubsub(client).subscribe("news", timeout: 0.4)

    assert_equal %w[news 1], client.last_command.args
  end

  def test_subscribe_rejects_a_negative_timeout
    client = RecordingClient.new

    assert_raises(ArgumentError) { build_pubsub(client).subscribe("news", timeout: -1) }
    assert_empty client.sent_commands
  end

  def test_subscribe_without_channels_raises
    client = RecordingClient.new

    error = assert_raises(ArgumentError) { build_pubsub(client).subscribe }

    assert_equal "No channels provided for subscription", error.message
    assert_empty client.sent_commands
  end

  def test_unsubscribe
    client = RecordingClient.new

    build_pubsub(client).unsubscribe("news", timeout: 3000)

    assert_equal Valkey::RequestType::UNSUBSCRIBE_BLOCKING, client.last_command.request_type
    assert_equal %w[news 3000], client.last_command.args
  end

  def test_unsubscribe_default
    client = RecordingClient.new

    build_pubsub(client).unsubscribe

    assert_equal Valkey::RequestType::UNSUBSCRIBE_BLOCKING, client.last_command.request_type
    assert_equal %w[0], client.last_command.args
  end

  def test_unsubscribe_rejects_a_negative_timeout
    client = RecordingClient.new

    assert_raises(ArgumentError) { build_pubsub(client).unsubscribe("news", timeout: -0.5) }
    assert_empty client.sent_commands
  end

  def test_publish_works_without_resp3
    client = RecordingClient.new(response: 0)

    Valkey::Glide::PubSub.new(client, cluster_mode: false).publish("hello", "news")

    assert_equal %w[news hello], client.last_command.args
  end

  # --- RESP3 requirement ---------------------------------------------------

  def test_subscription_methods_reject_a_non_resp3_protocol
    [nil, :resp2, "resp2", 2].each do |protocol|
      pubsub = build_pubsub(RecordingClient.new, protocol: protocol)

      guarded_calls(pubsub).each do |name, call|
        # Timeout so a missing guard fails the assertion instead of blocking in
        # get_message forever.
        error = assert_raises(Valkey::Resp3RequiredError, "#{name} must reject protocol #{protocol.inspect}") do
          Timeout.timeout(2) { call.call }
        end
        assert_match(/RESP3/, error.message)
      end
    end
  end

  def test_subscription_methods_accept_every_resp3_spelling
    [:resp3, "resp3", 3].each do |protocol|
      pubsub = build_pubsub(RecordingClient.new, protocol: protocol)

      pubsub.subscribe("news")
      pubsub.unsubscribe

      assert_nil pubsub.try_get_message, "protocol #{protocol.inspect} must be accepted"
      assert_equal "hello", queued_message(pubsub).message
    end
  end

  private

  def build_pubsub(client, protocol: :resp3)
    Valkey::Glide::PubSub.new(client, cluster_mode: false, protocol: protocol)
  end

  # get_message blocks, so it is only called on a queue that already holds one.
  def queued_message(pubsub)
    push(Kind::MESSAGE, message: "hello", channel: "news", pubsub: pubsub)
    pubsub.get_message
  end

  def guarded_calls(pubsub)
    {
      subscribe: -> { pubsub.subscribe("news") },
      unsubscribe: -> { pubsub.unsubscribe },
      get_message: -> { pubsub.get_message },
      try_get_message: -> { pubsub.try_get_message }
    }
  end

  # Calls the retained FFI handler the way the Rust push worker does, with real
  # buffers and the byte lengths alongside them.
  def push(kind, message: nil, channel: nil, pattern: nil, pubsub: nil)
    message_pointer, message_length = buffer_for(message)
    channel_pointer, channel_length = buffer_for(channel)
    pattern_pointer, pattern_length = buffer_for(pattern)

    (pubsub || @pubsub).ffi_handler.call(
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
