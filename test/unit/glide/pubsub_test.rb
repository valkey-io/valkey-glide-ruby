# frozen_string_literal: true

require "test_helper"
require "timeout"

# Unit tests for Valkey::Glide::PubSub.
# TODO: https://github.com/valkey-io/valkey-glide-ruby/issues/135.
class TestGlidePubSubUnit < Minitest::Test
  Kind = Valkey::Glide::PubSub::PushKind

  def setup
    @pubsub = Valkey::Glide::PubSub.new(nil, cluster_mode: false)
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
    error = assert_raises(ArgumentError) do
      Valkey::Glide::PubSub.parse_config({ subscriptions: { exact: ["news"] } }, protocol: :resp2)
    end
    assert_match(/RESP3/, error.message)
  end

  def test_pubsub_omitted_protocol_raises
    error = assert_raises(ArgumentError) do
      Valkey::Glide::PubSub.parse_config({ subscriptions: { exact: ["news"] } })
    end
    assert_match(/RESP3/, error.message)
  end

  def test_pubsub_explicit_nil_protocol_raises
    error = assert_raises(ArgumentError) do
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
end
