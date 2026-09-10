# frozen_string_literal: true

require "securerandom"
require "timeout"

# Pub/Sub integration tests.
module ValkeyTests
  module PubSub
    MESSAGE_WAIT_SECONDS = 5.0
    POLL_INTERVAL_SECONDS = 0.02

    # Wait time for unsubscribe tests.
    UNSUB_WAIT_TIME = 0.5

    def test_connection_time_subscription
      channel = unique_channel

      with_client(pubsub: { subscriptions: { exact: [channel] } }) do |client|
        # Uses try_get_pubsub_message polling underneath
        received = publish_until_received("connect-time", channel, client)

        assert_equal "connect-time", received.message
        assert_equal channel, received.channel
        assert_nil received.pattern
      end
    end

    def test_runtime_subscribe
      channel = unique_channel

      with_client do |client|
        client.subscribe(channel)
        r.publish("runtime", channel)
        received = wait_for_message(client)

        assert_equal "runtime", received.message
        assert_nil received.pattern
      end
    end

    def test_messages_arrive_in_order
      channel = unique_channel
      payloads = Array.new(5) { |index| "message-#{index}" }

      with_client do |client|
        client.subscribe(channel)
        payloads.each { |payload| r.publish(payload, channel) }

        received = payloads.map { wait_for_message(client).message }

        assert_equal payloads, received
      end
    end

    def test_binary_payload
      channel = unique_channel
      payload = (0..255).map(&:chr).join.b

      with_client do |client|
        client.subscribe(channel)
        r.publish(payload, channel)
        received = wait_for_message(client)

        assert_equal payload.bytesize, received.message.bytesize
        assert_equal payload.bytes, received.message.bytes
      end
    end

    def test_try_get_pubsub_message_empty_message_queue
      with_client do |client|
        client.subscribe(unique_channel)

        assert_nil client.try_get_pubsub_message
      end
    end

    def test_get_pubsub_message
      channel = unique_channel

      with_client do |client|
        client.subscribe(channel)
        reader = Thread.new { client.get_pubsub_message }

        refute reader.join(0.2), "get_pubsub_message returned before anything was published"

        r.publish("message", channel)
        received = Timeout.timeout(MESSAGE_WAIT_SECONDS) { reader.value }

        assert_equal "message", received.message
      end
    end

    # Ensure close unblocks a waiting get_pubsub_message
    def test_close_after_blocking_get_pubsub_message
      client = _new_client(protocol: :resp3)
      client.subscribe(unique_channel)
      reader = Thread.new { client.get_pubsub_message }

      refute reader.join(0.2), "get_pubsub_message returned before the client was closed"

      client.close

      assert_nil Timeout.timeout(MESSAGE_WAIT_SECONDS) { reader.value }
    ensure
      client.close
    end

    def test_publish_returns_the_receiver_count
      channel = unique_channel

      with_client do |first_subscriber|
        with_client do |second_subscriber|
          # No subscribers yet, so the count is zero
          assert_equal 0, first_subscriber.publish("message", channel)

          first_subscriber.subscribe(channel)
          second_subscriber.subscribe(channel)
          assert_equal 2, r.publish("counted", channel)
        end
      end
    end

    def test_unsubscribe
      channel = unique_channel

      with_client do |subscriber|
        subscriber.subscribe(channel)
        r.publish("first", channel)

        assert_equal "first", wait_for_message(subscriber).message

        subscriber.unsubscribe(channel)

        assert_equal 0, r.publish("second", channel)
        assert_nil wait_for_message(subscriber, timeout: UNSUB_WAIT_TIME)
      end
    end

    def test_unsubscribe_all
      channels = Array.new(3) { unique_channel }

      with_client do |subscriber|
        subscriber.subscribe(*channels)

        # Default to unsubscribe all channels
        subscriber.unsubscribe

        channels.each { |channel| assert_equal 0, r.publish("orphan", channel) }
        assert_nil wait_for_message(subscriber, timeout: UNSUB_WAIT_TIME)
      end
    end

    # The point of waiting for the server's acknowledgement: a publish issued
    # right after subscribe returns must already have a subscriber.
    def test_subscribe_blocks_until_channel_is_ready
      with_client do |subscriber|
        with_client do |publisher|
          5.times do |index|
            channel = unique_channel("confirmed-#{index}")
            subscriber.subscribe(channel)

            subscriber_count = publisher.publish("immediate-#{index}", channel)
            assert_equal 1, subscriber_count

            message = wait_for_message(subscriber).message
            assert_equal "immediate-#{index}", message
          end
        end
      end
    end

    def test_subscribe_and_unsubscribe_negative_timeout
      channel = unique_channel

      with_client do |subscriber|
        assert_raises(ArgumentError) { subscriber.subscribe(channel, timeout_ms: -1) }
        assert_raises(ArgumentError) { subscriber.unsubscribe(channel, timeout_ms: -0.5) }
      end
    end

    # Zero means "no deadline"; the server confirms a healthy subscription well
    # before the suite's own deadline, so this must not hang.
    def test_subscribe_and_unsubscribe_zero_timeout
      channel = unique_channel

      with_client do |subscriber|
        subscriber.subscribe(channel, timeout_ms: 0)
        publish_until_received("zero-timeout", channel, subscriber)
        subscriber.unsubscribe(channel, timeout_ms: 0)
      end
    end

    def test_subscribe_on_default_protocol
      # We currently default to RESP2, so this should raise.
      error = assert_raises(Valkey::Resp3RequiredError) { r.subscribe(unique_channel) }

      assert_match(/RESP3/, error.message)
    end

    def test_connection_time_subscription_with_resp2
      subscriptions = { subscriptions: { exact: [unique_channel] } }

      omitted_protocol = assert_raises(Valkey::Resp3RequiredError) { _new_client(pubsub: subscriptions) }
      explicit_resp2 = assert_raises(Valkey::Resp3RequiredError) do
        _new_client(protocol: :resp2, pubsub: subscriptions)
      end

      assert_match(/RESP3/, omitted_protocol.message)
      assert_match(/RESP3/, explicit_resp2.message)
    end

    # A GLIDE connection is not confined to subscriber mode the way redis-rb is.
    def test_subscribed_client_still_runs_ordinary_commands
      channel = unique_channel
      key = "pubsub-#{SecureRandom.hex(6)}"

      with_client do |subscriber|
        subscriber.subscribe(channel)
        subscriber.select(DB) unless cluster_mode?
        subscriber.set(key, "value")

        assert_equal "PONG", subscriber.ping
        assert_equal "value", subscriber.get(key)

        r.publish("after-command", channel)

        recv = wait_for_message(subscriber)
        assert_equal "after-command", recv.message
      end
    end

    private

    def with_client(options = {})
      subscriber = _new_client(options.merge(protocol: :resp3))
      yield subscriber
    ensure
      subscriber&.close
    end

    def unique_channel(suffix = nil)
      ["pubsub", Process.pid, SecureRandom.hex(6), suffix].compact.join("-")
    end

    def wait_for_message(subscriber, timeout: MESSAGE_WAIT_SECONDS)
      wait_until(timeout: timeout) { subscriber.try_get_pubsub_message }
    end

    def publish_until_received(message, channel, subscriber, timeout: MESSAGE_WAIT_SECONDS)
      deadline = monotonic_now + timeout

      loop do
        r.publish(message, channel)
        received = wait_for_message(subscriber, timeout: POLL_INTERVAL_SECONDS)
        return received if received

        flunk("no message on #{channel} within #{timeout}s") if monotonic_now >= deadline
      end
    end

    def wait_until(timeout: MESSAGE_WAIT_SECONDS)
      deadline = monotonic_now + timeout

      loop do
        result = yield
        return result if result
        return nil if monotonic_now >= deadline

        sleep POLL_INTERVAL_SECONDS
      end
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
