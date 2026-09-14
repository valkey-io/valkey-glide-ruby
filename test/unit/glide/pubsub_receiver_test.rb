# frozen_string_literal: true

require "test_helper"

class TestPubSubReceiverUnit < Minitest::Test
  Kind = Valkey::Glide::PubSubReceiver::PushKind

  def setup
    @receiver = Valkey::Glide::PubSubReceiver.new
  end

  def teardown
    @receiver&.close
  end

  def test_ffi_handler_queues_messages
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

  def test_ffi_handler_drops_non_message_kinds
    non_message_kinds = [
      Kind::DISCONNECTION, Kind::OTHER, Kind::INVALIDATE,
      Kind::SUBSCRIBE, Kind::PSUBSCRIBE, Kind::SSUBSCRIBE,
      Kind::UNSUBSCRIBE, Kind::PUNSUBSCRIBE, Kind::SUNSUBSCRIBE
    ]

    non_message_kinds.each do |kind|
      push(kind, message: "phantom", channel: "news")

      assert_nil @receiver.try_pop, "kind #{kind} must not queue a message"
    end
  end

  def test_ffi_handler_with_embedded_nul
    payload = "before\0after"

    push(Kind::MESSAGE, message: payload, channel: "news")

    assert_equal payload, @receiver.try_pop.message
  end

  private

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
