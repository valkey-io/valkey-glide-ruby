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

    def test_psubscribe_delivers_message_with_pattern
      pattern = "pubsub-p-#{SecureRandom.hex(6)}.*"
      channel = pattern.sub(".*", ".tech")

      with_client do |subscriber|
        subscriber.psubscribe(pattern)
        r.publish("pattern-msg", channel)
        msg = wait_for_message(subscriber)

        assert_equal "pattern-msg", msg.message
        assert_equal channel,       msg.channel
        assert_equal pattern,       msg.pattern
      end
    end

    def test_punsubscribe_stops_pattern_delivery
      pattern = "pubsub-punsub-#{SecureRandom.hex(6)}.*"
      channel = pattern.sub(".*", ".x")

      with_client do |subscriber|
        subscriber.psubscribe(pattern)
        r.publish("before", channel)
        assert_equal "before", wait_for_message(subscriber).message

        subscriber.punsubscribe(pattern)

        r.publish("after", channel)
        assert_nil wait_for_message(subscriber, timeout: UNSUB_WAIT_TIME)
      end
    end

    def test_punsubscribe_without_patterns_stops_every_pattern
      first  = "pubsub-punsub-all-#{SecureRandom.hex(6)}.*"
      second = "pubsub-punsub-all-#{SecureRandom.hex(6)}.*"

      with_client do |subscriber|
        subscriber.psubscribe(first, second)
        r.publish("before", first.sub(".*", ".x"))
        assert_equal "before", wait_for_message(subscriber).message

        subscriber.punsubscribe

        assert_delivery_ceased(first.sub(".*", ".x"), subscriber)
        assert_delivery_ceased(second.sub(".*", ".y"), subscriber)
      end
    end

    def test_subscribe_lazy_eventually_delivers
      channel = unique_channel

      with_client do |subscriber|
        subscriber.subscribe_lazy(channel)

        received = publish_until_received("lazy-msg", channel, subscriber)

        assert_equal "lazy-msg", received.message
        assert_equal channel,    received.channel
        assert_nil               received.pattern
      end
    end

    def test_psubscribe_lazy_eventually_delivers_messages
      pattern = "pubsub-lazy-p-#{SecureRandom.hex(6)}.*"
      channel = pattern.sub(".*", ".y")

      with_client do |subscriber|
        subscriber.psubscribe_lazy(pattern)

        received = publish_until_received("lazy-pattern-msg", channel, subscriber)

        assert_equal "lazy-pattern-msg", received.message
        assert_equal channel,            received.channel
        assert_equal pattern,            received.pattern
      end
    end

    def test_unsubscribe_lazy_eventually_stops_delivery
      channel = unique_channel

      with_client do |subscriber|
        subscriber.subscribe_lazy(channel)
        publish_until_received("before", channel, subscriber)

        subscriber.unsubscribe_lazy(channel)

        assert_delivery_ceased(channel, subscriber)
      end
    end

    def test_punsubscribe_lazy_eventually_stops_delivery
      pattern = "pubsub-lazy-punsub-#{SecureRandom.hex(6)}.*"
      channel = pattern.sub(".*", ".z")

      with_client do |subscriber|
        subscriber.psubscribe_lazy(pattern)
        publish_until_received("before", channel, subscriber)

        subscriber.punsubscribe_lazy(pattern)

        assert_delivery_ceased(channel, subscriber)
      end
    end

    def test_unsubscribe_lazy_without_channels_stops_every_channel
      first  = unique_channel("unsub-all-1")
      second = unique_channel("unsub-all-2")

      with_client do |subscriber|
        subscriber.subscribe(first, second)
        publish_until_received("before", first, subscriber)

        subscriber.unsubscribe_lazy

        assert_delivery_ceased(first, subscriber)
        assert_delivery_ceased(second, subscriber)
      end
    end

    def test_punsubscribe_lazy_without_patterns_stops_every_pattern
      first  = "pubsub-lazy-punsub-all-#{SecureRandom.hex(6)}.*"
      second = "pubsub-lazy-punsub-all-#{SecureRandom.hex(6)}.*"

      with_client do |subscriber|
        subscriber.psubscribe(first, second)
        publish_until_received("before", first.sub(".*", ".x"), subscriber)

        subscriber.punsubscribe_lazy

        assert_delivery_ceased(first.sub(".*", ".x"), subscriber)
        assert_delivery_ceased(second.sub(".*", ".y"), subscriber)
      end
    end

    def test_lazy_verbs_return_nil_without_waiting_for_the_server
      channel = unique_channel
      pattern = "pubsub-lazy-nil-#{SecureRandom.hex(6)}.*"

      with_client do |subscriber|
        returned = Timeout.timeout(MESSAGE_WAIT_SECONDS) do
          [
            subscriber.subscribe_lazy(channel),
            subscriber.psubscribe_lazy(pattern),
            subscriber.unsubscribe_lazy(channel),
            subscriber.punsubscribe_lazy(pattern)
          ]
        end

        assert_equal [nil, nil, nil, nil], returned
      end
    end

    def test_callback_mode_delivers_messages_end_to_end
      channel = unique_channel
      ctx     = { origin: "e2e-test" }
      queue   = Thread::Queue.new

      subscriber = _new_client(
        protocol: :resp3,
        pubsub: {
          subscriptions: { exact: [channel] },
          callback: ->(msg, callback_ctx) { queue.push([msg, callback_ctx]) },
          context: ctx
        }
      )

      pair = collect_callback_message(queue, "callback-msg", channel)

      msg, delivered_ctx = pair
      assert_equal "callback-msg", msg.message
      assert_equal channel,        msg.channel
      assert_nil                   msg.pattern
      assert_same ctx,             delivered_ctx
    ensure
      subscriber&.close
    end

    def test_callback_mode_delivers_pattern_messages_with_the_pattern
      pattern = "pubsub-cb-p-#{SecureRandom.hex(6)}.*"
      channel = pattern.sub(".*", ".tech")
      queue   = Thread::Queue.new

      subscriber = _new_client(
        protocol: :resp3,
        pubsub: {
          subscriptions: { pattern: [pattern] },
          callback: ->(msg, _callback_ctx) { queue.push(msg) }
        }
      )

      msg = collect_callback_message(queue, "callback-pattern-msg", channel)

      assert_equal "callback-pattern-msg", msg.message
      assert_equal channel,                msg.channel
      assert_equal pattern,                msg.pattern
    ensure
      subscriber&.close
    end

    def test_callback_exception_is_contained
      channel    = unique_channel
      boom_token = "boom-#{SecureRandom.hex(4)}"
      safe_token = "safe-#{SecureRandom.hex(4)}"
      invoked    = Thread::Queue.new
      recovered  = Thread::Queue.new

      callback = lambda do |msg, _ctx|
        if msg.message == boom_token
          invoked.push(msg.message)
          raise "deliberate callback error"
        else
          recovered.push(msg.message)
        end
      end

      subscriber = _new_client(
        protocol: :resp3,
        pubsub: {
          subscriptions: { exact: [channel] },
          callback: callback,
          context: nil
        }
      )

      collect_callback_message(invoked, boom_token, channel)

      second = collect_callback_message(recovered, safe_token, channel)

      assert_equal safe_token, second
    ensure
      subscriber&.close
    end

    # --- Sharded Pub/Sub (cluster mode) --------------------------------------

    def test_sharded_message_round_trip
      skip_unless_sharded_pubsub

      channel = unique_channel

      with_client do |subscriber|
        subscriber.ssubscribe(channel)
        r.publish("sharded-msg", channel, sharded: true)
        received = wait_for_message(subscriber)

        assert_equal "sharded-msg", received.message
        assert_equal channel,       received.channel
        assert_nil                  received.pattern
      end
    end

    def test_spublish_returns_the_receiver_count
      skip_unless_sharded_pubsub

      channel = unique_channel

      with_client do |subscriber|
        assert_equal 0, r.publish("nobody", channel, sharded: true)

        subscriber.ssubscribe(channel)
        assert_equal 1, r.publish("counted", channel, sharded: true)
      end
    end

    def test_sunsubscribe_stops_sharded_delivery
      skip_unless_sharded_pubsub

      channel = unique_channel

      with_client do |subscriber|
        subscriber.ssubscribe(channel)
        r.publish("before", channel, sharded: true)
        assert_equal "before", wait_for_message(subscriber).message

        subscriber.sunsubscribe(channel)

        assert_equal 0, r.publish("after", channel, sharded: true)
        assert_nil wait_for_message(subscriber, timeout: UNSUB_WAIT_TIME)
      end
    end

    def test_sunsubscribe_all_sharded_channels
      skip_unless_sharded_pubsub

      # Same hash tag keeps both channels in one slot, so a single ssubscribe
      # call is routed to one node and both land in the actual subscriptions.
      channels = Array.new(2) { |i| unique_channel("{shardtag}-#{i}") }

      with_client do |subscriber|
        subscriber.ssubscribe(*channels)

        subscriber.sunsubscribe

        channels.each { |channel| assert_equal 0, r.publish("orphan", channel, sharded: true) }
        assert_nil wait_for_message(subscriber, timeout: UNSUB_WAIT_TIME)
      end
    end

    def test_ssubscribe_lazy_eventually_delivers
      skip_unless_sharded_pubsub

      channel = unique_channel

      with_client do |subscriber|
        subscriber.ssubscribe_lazy(channel)

        received = publish_until_received_sharded("lazy-sharded-msg", channel, subscriber)

        assert_equal "lazy-sharded-msg", received.message
        assert_equal channel,            received.channel
        assert_nil                       received.pattern
      end
    end

    def test_sunsubscribe_lazy_eventually_stops_delivery
      skip_unless_sharded_pubsub

      channel = unique_channel

      with_client do |subscriber|
        subscriber.ssubscribe_lazy(channel)
        publish_until_received_sharded("before", channel, subscriber)

        subscriber.sunsubscribe_lazy(channel)

        assert_delivery_ceased(channel, subscriber, sharded: true)
      end
    end

    def test_connection_time_sharded_subscription
      skip_unless_sharded_pubsub

      channel = unique_channel

      with_client(pubsub: { subscriptions: { sharded: [channel] } }) do |client|
        received = publish_until_received_sharded("connect-time-sharded", channel, client)

        assert_equal "connect-time-sharded", received.message
        assert_equal channel, received.channel
        assert_nil received.pattern
      end
    end

    def test_sharded_publish_reaches_a_subscriber_in_a_different_slot
      skip_unless_sharded_pubsub

      # Distinct hash tags force the two channels onto different slots (and thus
      # likely different owning nodes). A same-slot pair would pass even if the
      # SPUBLISH were misrouted, so the different-slot case is what proves the
      # publish is routed by the channel it names, not the subscriber's node.
      subscribed_channel = unique_channel("{slot-a}")
      other_slot_channel = unique_channel("{slot-b}")

      with_client do |subscriber|
        subscriber.ssubscribe(subscribed_channel)

        # A message on a channel in a different slot must not arrive here.
        r.publish("wrong-slot", other_slot_channel, sharded: true)
        assert_nil wait_for_message(subscriber, timeout: UNSUB_WAIT_TIME)

        # A message on the subscribed channel must arrive, proving the SPUBLISH
        # was routed to the node owning that channel's slot.
        r.publish("right-slot", subscribed_channel, sharded: true)
        assert_equal "right-slot", wait_for_message(subscriber).message
      end
    end

    def test_sharded_publish_is_batchable_in_a_pipeline
      skip_unless_sharded_pubsub

      channel = unique_channel

      with_client do |subscriber|
        subscriber.ssubscribe(channel)

        counts = r.pipelined { |p| p.publish("piped", channel, sharded: true) }

        assert_equal [1], counts
        assert_equal "piped", wait_for_message(subscriber).message
      end
    end

    def test_sharded_verbs_require_cluster_mode_in_standalone
      skip "covers the standalone rejection path" if cluster_mode?

      with_client do |client|
        {
          ssubscribe: -> { client.ssubscribe("shard1") },
          sunsubscribe: -> { client.sunsubscribe },
          ssubscribe_lazy: -> { client.ssubscribe_lazy("shard1") },
          sunsubscribe_lazy: -> { client.sunsubscribe_lazy }
        }.each do |name, call|
          error = assert_raises(ArgumentError, "#{name} must require cluster mode") { call.call }
          assert_match(/cluster mode/, error.message)
        end
      end
    end

    def test_sharded_connection_config_requires_cluster_mode_in_standalone
      skip "covers the standalone rejection path" if cluster_mode?

      error = assert_raises(ArgumentError) do
        _new_client(protocol: :resp3, pubsub: { subscriptions: { sharded: [unique_channel] } })
      end

      assert_match(/cluster mode/, error.message)
    end

    SUBSCRIPTION_MODE_KEYS = %i[exact pattern sharded].freeze
    NON_BATCHABLE_PUBSUB_COMMANDS = %i[
      subscribe unsubscribe psubscribe punsubscribe ssubscribe sunsubscribe
      subscribe_lazy unsubscribe_lazy psubscribe_lazy punsubscribe_lazy
      ssubscribe_lazy sunsubscribe_lazy
      get_subscriptions get_pubsub_message try_get_pubsub_message
    ].freeze

    def test_get_subscriptions_tracks_subscribe_and_unsubscribe
      channel = unique_channel

      with_client do |subscriber|
        subscriber.subscribe(channel)

        state = subscriber.get_subscriptions
        assert_kind_of Valkey::Glide::PubSubState, state
        assert_empty state.desired_subscriptions.keys - SUBSCRIPTION_MODE_KEYS
        assert_empty state.actual_subscriptions.keys - SUBSCRIPTION_MODE_KEYS
        assert_includes state.desired_subscriptions.fetch(:exact, []), channel
        assert_includes state.actual_subscriptions.fetch(:exact, []), channel

        subscriber.unsubscribe(channel)

        state = subscriber.get_subscriptions
        refute_includes state.desired_subscriptions.fetch(:exact, []), channel
        refute_includes state.actual_subscriptions.fetch(:exact, []), channel
      end
    end

    def test_introspection_sees_another_clients_subscription
      channel = unique_channel

      with_client do |subscriber|
        subscriber.subscribe(channel)

        assert_includes r.pubsub_channels, channel
        assert_includes r.pubsub_channels("#{channel}*"), channel
        assert_numsub({ channel => 1 }, r.pubsub_numsub(channel))
      end
    end

    def test_pubsub_numpat_tracks_pattern_subscriptions
      pattern = "#{unique_channel}*"
      initial_count = r.pubsub_numpat

      with_client do |subscriber|
        subscriber.psubscribe(pattern)

        begin
          assert_equal initial_count + 1, r.pubsub_numpat
        ensure
          subscriber.punsubscribe(pattern)
        end

        assert_equal initial_count, r.pubsub_numpat
      end
    end

    # Python sync exercises the Pub/Sub batch surface in both atomic and
    # non-atomic batches, under RESP2 and RESP3. Keep these two entry points
    # separate so a regression identifies which Ruby API failed.
    def test_pubsub_commands_in_pipeline
      assert_pubsub_batch_commands(:pipelined)
    end

    def test_pubsub_commands_in_multi
      assert_pubsub_batch_commands(:multi)
    end

    def test_empty_pubsub_results_in_pipeline
      assert_empty_pubsub_batch_results(:pipelined)
    end

    def test_empty_pubsub_results_in_multi
      assert_empty_pubsub_batch_results(:multi)
    end

    def test_sharded_pubsub_batch_commands_require_cluster_mode
      skip("standalone-only: Python exposes these methods only on ClusterBatch") if cluster_mode?

      %i[pipelined multi].each do |batch_method|
        calls = {
          publish: ->(batch) { batch.publish("message", unique_channel, sharded: true) },
          pubsub_shardchannels: ->(batch) { batch.pubsub_shardchannels(nil) },
          pubsub_shardnumsub: ->(batch) { batch.pubsub_shardnumsub(unique_channel) }
        }

        calls.each do |name, call|
          error = assert_raises(ArgumentError, "#{name} must require cluster mode in #{batch_method}") do
            r.public_send(batch_method) { |batch| call.call(batch) }
          end

          assert_match(/cluster mode/, error.message)
        end
      end
    end

    def test_non_batchable_pubsub_commands_are_rejected
      assert_equal NON_BATCHABLE_PUBSUB_COMMANDS, Valkey::Pipeline::PUBSUB_UNSUPPORTED

      NON_BATCHABLE_PUBSUB_COMMANDS.each do |name|
        %i[pipelined multi].each do |batch_method|
          error = assert_raises(ArgumentError, "#{name} must be rejected by #{batch_method}") do
            r.public_send(batch_method) { |pipeline| pipeline.public_send(name) }
          end

          assert_equal "#{name} is not supported inside pipelined/multi", error.message
        end
      end
    end

    def test_pubsub_channels_aggregates_across_nodes
      skip("cluster-only: exercises the core's cross-node fan-out") unless cluster_mode?

      channels = %w[{bar} {key1} {foo}].map { |tag| unique_channel(tag) }

      subscribers = channels.map do |channel|
        subscriber = _new_client(protocol: :resp3)
        subscriber.subscribe(channel)
        subscriber
      end

      seen = r.pubsub_channels

      channels.each do |channel|
        assert_includes seen, channel
        assert_equal 1, seen.count(channel), "expected #{channel} exactly once in #{seen.inspect}"
      end

      assert_numsub channels.to_h { |channel| [channel, 1] }, r.pubsub_numsub(*channels)
    ensure
      subscribers&.each(&:close)
    end

    def test_shard_introspection_shapes
      skip("cluster-only: sharded Pub/Sub commands") unless cluster_mode?
      omit_version("7.0")

      channel = unique_channel

      shard_channels = r.pubsub_shardchannels
      assert_kind_of Array, shard_channels
      shard_channels.each { |shard_channel| assert_kind_of String, shard_channel }
      assert_kind_of Array, r.pubsub_shardchannels("#{channel}*")

      assert_numsub({ channel => 0 }, r.pubsub_shardnumsub(channel))
    end

    private

    def skip_unless_sharded_pubsub
      skip "sharded Pub/Sub is cluster-only" unless cluster_mode?

      omit_version("7.0")
    end

    def assert_empty_pubsub_batch_results(batch_method)
      %i[resp2 resp3].each do |protocol|
        channel = unique_channel("{empty-#{batch_method}-#{protocol}}")
        supports_sharded = cluster_mode? && version >= "7.0"
        batch_client = _new_client(protocol: protocol)
        futures = []

        results = batch_client.public_send(batch_method) do |batch|
          futures << batch.publish("orphan", channel)
          futures << batch.pubsub_channels(channel)
          futures << batch.pubsub_numpat
          futures << batch.pubsub_numsub

          if supports_sharded
            futures << batch.publish("sharded-orphan", channel, sharded: true)
            futures << batch.pubsub_shardchannels(channel)
            futures << batch.pubsub_shardnumsub
          end
        end

        assert_equal results, futures.map(&:value)
        assert_equal 0, results[0]
        assert_empty results[1]
        assert_equal 0, results[2]
        assert_numsub({}, results[3])

        next unless supports_sharded

        assert_equal 0, results[4]
        assert_empty results[5]
        assert_numsub({}, results[6])
      ensure
        batch_client&.close
      end
    end

    def assert_pubsub_batch_commands(batch_method)
      %i[resp2 resp3].each do |protocol|
        assert_pubsub_batch_commands_for_protocol(batch_method, protocol)
      end
    end

    def assert_pubsub_batch_commands_for_protocol(batch_method, protocol)
      channel = unique_channel("{#{batch_method}-#{protocol}}")
      regular_message = "regular-#{batch_method}-#{protocol}"
      sharded_message = "sharded-#{batch_method}-#{protocol}"
      supports_sharded = cluster_mode? && version >= "7.0"
      batch_client = nil

      with_client do |subscriber|
        subscriber.subscribe(channel)
        subscriber.ssubscribe(channel) if supports_sharded
        batch_client = _new_client(protocol: protocol)

        results = batch_client.public_send(batch_method) do |batch|
          batch.publish(regular_message, channel)
          batch.pubsub_channels(channel)
          batch.pubsub_numpat
          batch.pubsub_numsub(channel)

          if supports_sharded
            batch.publish(sharded_message, channel, sharded: true)
            batch.pubsub_shardchannels(channel)
            batch.pubsub_shardnumsub(channel)
          end
        end

        assert_equal 1, results[0]
        assert_equal [channel], results[1]
        assert_kind_of Integer, results[2]
        assert_numsub({ channel => 1 }, results[3])

        expected_messages = [regular_message]
        if supports_sharded
          assert_equal 1, results[4]
          assert_equal [channel], results[5]
          assert_numsub({ channel => 1 }, results[6])
          expected_messages << sharded_message
        end

        actual_messages = expected_messages.length.times.map { wait_for_message(subscriber).message }
        assert_equal expected_messages.sort, actual_messages.sort
      ensure
        batch_client&.close
      end
    end

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

    def publish_until_received_sharded(message, channel, subscriber, timeout: MESSAGE_WAIT_SECONDS)
      deadline = monotonic_now + timeout

      loop do
        r.publish(message, channel, sharded: true)
        received = wait_for_message(subscriber, timeout: POLL_INTERVAL_SECONDS)
        return received if received

        flunk("no sharded message on #{channel} within #{timeout}s") if monotonic_now >= deadline
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

    def collect_callback_message(queue, payload, channel, timeout: MESSAGE_WAIT_SECONDS)
      deadline = monotonic_now + timeout

      loop do
        r.publish(payload, channel)

        begin
          return queue.pop(true)
        rescue ThreadError
          flunk("callback queue got nothing for #{payload.inspect} within #{timeout}s") if monotonic_now >= deadline

          sleep POLL_INTERVAL_SECONDS
          retry
        end
      end
    end

    def assert_delivery_ceased(channel, subscriber, sharded: false)
      quiet_windows = 2
      deadline = monotonic_now + MESSAGE_WAIT_SECONDS
      quiet_count = 0

      until quiet_count >= quiet_windows
        flunk("delivery did not cease on #{channel} within #{MESSAGE_WAIT_SECONDS}s") if monotonic_now >= deadline

        r.publish("probe-ceased-#{SecureRandom.hex(4)}", channel, sharded: sharded)
        message = wait_for_message(subscriber, timeout: UNSUB_WAIT_TIME)

        if message
          nil while subscriber.try_get_pubsub_message
          quiet_count = 0
        else
          quiet_count += 1
        end
      end
    end
  end
end
