# frozen_string_literal: true

require "test_helper"
require "timeout"

# Unit tests for Valkey::Commands::PubSubCommands.
# TODO: https://github.com/valkey-io/valkey-glide-ruby/issues/135.
class TestPubSubCommandsUnit < Minitest::Test
  Kind = Valkey::Glide::PubSubReceiver::PushKind

  # A real client with the connection left out, so the mixin's own methods run
  # unmodified while dispatch is asserted without a server: records what would
  # have gone over the wire and replies with a canned value.
  class RecordingClient < Valkey
    SentCommand = Struct.new(:request_type, :args)

    attr_reader :sent_commands

    def initialize(response: nil, protocol: :resp3, callback: nil, cluster_mode: false) # rubocop:disable Lint/MissingSuper
      @sent_commands = []
      @response = response
      @protocol = protocol
      @cluster_mode = cluster_mode
      @pubsub_receiver = Valkey::Glide::PubSubReceiver.new(callback: callback)
      @close_lock = Mutex.new
      @pid = Process.pid
    end

    def send_command(request_type, args = [], **_options, &block)
      @sent_commands << SentCommand.new(request_type, args)
      block ? block.call(@response) : @response
    end

    def last_command
      @sent_commands.last
    end
  end

  # Pub/Sub requires RESP3, so the shared instance declares it; the protocol
  # guard itself is exercised with purpose-built instances further down.
  def setup
    @pubsub = RecordingClient.new
  end

  def teardown
    @pubsub&.close
  end

  # Enqueues without going through the FFI, so the queue contract can be tested
  # apart from the handler. In production only the handler enqueues.
  def deliver(message:, channel:, pattern: nil)
    enqueue(@pubsub, Valkey::Glide::PubSubMessage.new(message, channel, pattern))
  end

  def test_message_kinds_cover_only_payload_carrying_pushes
    assert_equal [Kind::MESSAGE, Kind::PMESSAGE, Kind::SMESSAGE], Kind::MESSAGE_KINDS
    refute_includes Kind::MESSAGE_KINDS, Kind::SUBSCRIBE
    refute_includes Kind::MESSAGE_KINDS, Kind::DISCONNECTION
  end

  def test_message_carries_message_channel_and_pattern
    msg = Valkey::Glide::PubSubMessage.new("hello", "news.tech", "news.*")

    assert_equal "hello", msg.message
    assert_equal "news.tech", msg.channel
    assert_equal "news.*", msg.pattern
  end

  def test_try_get_pubsub_message_returns_nil_when_empty
    assert_nil @pubsub.try_get_pubsub_message
  end

  def test_get_pubsub_message_returns_messages_in_delivery_order
    3.times { |i| deliver(message: "m#{i}", channel: "news") }

    received = 3.times.map { @pubsub.get_pubsub_message.message }

    assert_equal %w[m0 m1 m2], received
  end

  def test_close_wakes_a_blocked_reader_with_nil
    reader = Thread.new { @pubsub.get_pubsub_message }
    # Let the reader reach the blocking pop before the queue closes.
    sleep 0.05
    @pubsub.close

    assert_nil Timeout.timeout(2) { reader.value }
  end

  def test_try_get_pubsub_message_returns_nil_once_closed
    @pubsub.close

    assert_nil @pubsub.try_get_pubsub_message
  end

  # --- Pub/Sub connection options -----------------------------------------

  def test_pubsub_explicit_resp2_raises
    error = assert_raises(Valkey::Resp3RequiredError) do
      parse_pubsub_configs.call({ subscriptions: { exact: ["news"] } }, protocol: :resp2)
    end
    assert_match(/RESP3/, error.message)
  end

  def test_pubsub_omitted_protocol_raises
    error = assert_raises(Valkey::Resp3RequiredError) do
      parse_pubsub_configs.call({ subscriptions: { exact: ["news"] } })
    end
    assert_match(/RESP3/, error.message)
  end

  def test_pubsub_explicit_nil_protocol_raises
    error = assert_raises(Valkey::Resp3RequiredError) do
      parse_pubsub_configs.call({ subscriptions: { exact: ["news"] } }, protocol: nil)
    end
    assert_match(/RESP3/, error.message)
  end

  def test_pubsub_parse_config_ok
    pubsub_config = {
      subscriptions: { exact: ["news", :symbols], pattern: ["news.*"], sharded: ["news.shard"] }
    }

    parsed = parse_pubsub_configs.call(pubsub_config, protocol: :resp3, cluster_mode: true)

    expected = { "pubsub_subscriptions" => { "0" => %w[news symbols], "1" => ["news.*"], "2" => ["news.shard"] } }

    assert_equal expected, parsed
  end

  def test_pubsub_parse_config_without_sharded_does_not_require_cluster_mode
    pubsub_config = { subscriptions: { exact: ["news"], pattern: ["news.*"] } }

    parsed = parse_pubsub_configs.call(pubsub_config, protocol: :resp3)

    assert_equal({ "pubsub_subscriptions" => { "0" => ["news"], "1" => ["news.*"] } }, parsed)
  end

  def test_pubsub_sharded_config_requires_cluster_mode
    error = assert_raises(ArgumentError) do
      parse_pubsub_configs.call({ subscriptions: { sharded: ["shard-chan"] } }, protocol: :resp3)
    end

    assert_match(/cluster mode/, error.message)
  end

  def test_pubsub_parse_config_nil
    config = parse_pubsub_configs.call(nil)
    expected = parse_pubsub_configs.call({})
    assert_equal config, expected
  end

  def test_pubsub_unknown_subscription_mode_raises
    error = assert_raises(ArgumentError) do
      parse_pubsub_configs.call({ subscriptions: { unknown_mode: ["news.*"] } })
    end

    assert_equal "Unknown Pub/Sub subscription mode(s): unknown_mode. Valid modes are: exact, pattern, sharded",
                 error.message
  end

  # --- Command dispatch ----------------------------------------------------

  def test_subscribe
    client = RecordingClient.new

    client.subscribe("news", "alerts", timeout_ms: 2000)

    assert_equal Valkey::RequestType::SUBSCRIBE_BLOCKING, client.last_command.request_type
    assert_equal %w[news alerts 2000], client.last_command.args
  end

  def test_subscribe_with_default
    client = RecordingClient.new
    client.subscribe("news")

    assert_equal %w[news 0], client.last_command.args
  end

  def test_subscribe_fractional_milliseconds
    client = RecordingClient.new

    client.subscribe("news", timeout_ms: 1500.6)
    client.subscribe("news", timeout_ms: 250.2)

    assert_equal %w[news 1500], client.sent_commands[0].args
    assert_equal %w[news 250], client.sent_commands[1].args
  end

  def test_subscribe_sub_milliseconds_timeout
    client = RecordingClient.new

    client.subscribe("news", timeout_ms: 0.4)

    assert_equal %w[news 1], client.last_command.args
  end

  def test_subscribe_rejects_a_negative_timeout
    client = RecordingClient.new

    assert_raises(ArgumentError) { client.subscribe("news", timeout_ms: -1) }
    assert_empty client.sent_commands
  end

  def test_subscribe_without_channels_raises
    client = RecordingClient.new

    error = assert_raises(ArgumentError) { client.subscribe }

    assert_equal "No channels provided for subscription", error.message
    assert_empty client.sent_commands
  end

  def test_unsubscribe
    client = RecordingClient.new

    client.unsubscribe("news", timeout_ms: 3000)

    assert_equal Valkey::RequestType::UNSUBSCRIBE_BLOCKING, client.last_command.request_type
    assert_equal %w[news 3000], client.last_command.args
  end

  def test_unsubscribe_default
    client = RecordingClient.new

    client.unsubscribe

    assert_equal Valkey::RequestType::UNSUBSCRIBE_BLOCKING, client.last_command.request_type
    assert_equal %w[0], client.last_command.args
  end

  def test_unsubscribe_rejects_a_negative_timeout
    client = RecordingClient.new

    assert_raises(ArgumentError) { client.unsubscribe("news", timeout_ms: -0.5) }
    assert_empty client.sent_commands
  end

  def test_psubscribe
    client = RecordingClient.new

    client.psubscribe("news.*", "events.*", timeout_ms: 2000)

    assert_equal Valkey::RequestType::PSUBSCRIBE_BLOCKING, client.last_command.request_type
    assert_equal %w[news.* events.* 2000], client.last_command.args
  end

  def test_psubscribe_with_default
    client = RecordingClient.new

    client.psubscribe("news.*")

    assert_equal %w[news.* 0], client.last_command.args
  end

  def test_psubscribe_fractional_milliseconds
    client = RecordingClient.new

    client.psubscribe("news.*", timeout_ms: 1500.6)
    client.psubscribe("news.*", timeout_ms: 250.2)

    assert_equal %w[news.* 1500], client.sent_commands[0].args
    assert_equal %w[news.* 250], client.sent_commands[1].args
  end

  def test_psubscribe_sub_milliseconds_timeout
    client = RecordingClient.new

    client.psubscribe("news.*", timeout_ms: 0.4)

    assert_equal %w[news.* 1], client.last_command.args
  end

  def test_psubscribe_rejects_a_negative_timeout
    client = RecordingClient.new

    assert_raises(ArgumentError) { client.psubscribe("news.*", timeout_ms: -1) }
    assert_empty client.sent_commands
  end

  def test_psubscribe_without_patterns_raises
    client = RecordingClient.new

    error = assert_raises(ArgumentError) { client.psubscribe }

    assert_equal "No patterns provided for subscription", error.message
    assert_empty client.sent_commands
  end

  def test_punsubscribe
    client = RecordingClient.new

    client.punsubscribe("news.*", timeout_ms: 3000)

    assert_equal Valkey::RequestType::PUNSUBSCRIBE_BLOCKING, client.last_command.request_type
    assert_equal %w[news.* 3000], client.last_command.args
  end

  def test_punsubscribe_default
    client = RecordingClient.new

    client.punsubscribe

    assert_equal Valkey::RequestType::PUNSUBSCRIBE_BLOCKING, client.last_command.request_type
    assert_equal %w[0], client.last_command.args
  end

  def test_punsubscribe_sub_milliseconds_timeout
    client = RecordingClient.new

    client.punsubscribe("news.*", timeout_ms: 0.4)

    assert_equal %w[news.* 1], client.last_command.args
  end

  def test_punsubscribe_rejects_a_negative_timeout
    client = RecordingClient.new

    assert_raises(ArgumentError) { client.punsubscribe("news.*", timeout_ms: -0.5) }
    assert_empty client.sent_commands
  end

  def test_lazy_verbs_dispatch_without_a_timeout_argument
    client = RecordingClient.new

    client.subscribe_lazy("news")
    client.unsubscribe_lazy("news")
    client.psubscribe_lazy("news.*")
    client.punsubscribe_lazy("news.*")

    expected = [
      [Valkey::RequestType::SUBSCRIBE, %w[news]],
      [Valkey::RequestType::UNSUBSCRIBE, %w[news]],
      [Valkey::RequestType::PSUBSCRIBE, %w[news.*]],
      [Valkey::RequestType::PUNSUBSCRIBE, %w[news.*]]
    ]

    assert_equal(expected, client.sent_commands.map { |command| [command.request_type, command.args] })
  end

  def test_lazy_verbs_return_nil
    client = RecordingClient.new

    returned = [
      client.subscribe_lazy("news"),
      client.unsubscribe_lazy("news"),
      client.psubscribe_lazy("news.*"),
      client.punsubscribe_lazy("news.*")
    ]

    assert_equal [nil, nil, nil, nil], returned
  end

  def test_inline_reads_raise_on_a_callback_mode_client
    client = RecordingClient.new(callback: ->(_message, _context) {})

    %i[get_pubsub_message try_get_pubsub_message].each do |name|
      # Timeout so a missing guard fails the assertion instead of blocking in
      # get_pubsub_message forever.
      error = assert_raises(Valkey::InvalidClientOptionError, "#{name} must reject a callback-mode client") do
        Timeout.timeout(2) { client.public_send(name) }
      end

      assert_match(%r{Inline Pub/Sub reads are unavailable}, error.message)
    end
  end

  def test_lazy_unsubscribe_verbs_no_args
    client = RecordingClient.new

    client.unsubscribe_lazy
    client.punsubscribe_lazy

    assert_equal [[], []], client.sent_commands.map(&:args)
  end

  def test_subscribe_lazy_without_channels_raises
    client = RecordingClient.new

    error = assert_raises(ArgumentError) { client.subscribe_lazy }

    assert_equal "No channels provided for subscription", error.message
    assert_empty client.sent_commands
  end

  def test_psubscribe_lazy_without_patterns_raises
    client = RecordingClient.new

    error = assert_raises(ArgumentError) { client.psubscribe_lazy }

    assert_equal "No patterns provided for subscription", error.message
    assert_empty client.sent_commands
  end

  def test_subscription_verbs_coerce_their_arguments_to_strings
    client = RecordingClient.new

    client.psubscribe(:'news.*', 42, timeout_ms: 5)
    client.punsubscribe(:'news.*', 42, timeout_ms: 5)
    client.subscribe_lazy(:news, 42)
    client.unsubscribe_lazy(:news, 42)
    client.psubscribe_lazy(:'news.*', 42)
    client.punsubscribe_lazy(:'news.*', 42)

    expected = [
      %w[news.* 42 5], %w[news.* 42 5],
      %w[news 42], %w[news 42],
      %w[news.* 42], %w[news.* 42]
    ]

    assert_equal expected, client.sent_commands.map(&:args)
  end

  def test_publish_works_without_resp3
    client = RecordingClient.new(response: 0, protocol: nil)

    client.publish("hello", "news")

    assert_equal %w[news hello], client.last_command.args
  end

  # --- Sharded Pub/Sub (cluster mode) --------------------------------------

  def test_publish_defaults_to_unsharded
    client = RecordingClient.new(response: 0)

    client.publish("hello", "news")

    assert_equal Valkey::RequestType::PUBLISH, client.last_command.request_type
    assert_equal %w[news hello], client.last_command.args
  end

  def test_publish_sharded_uses_spublish_with_channel_first
    client = RecordingClient.new(response: 0, cluster_mode: true)

    client.publish("hello", "shard-chan", sharded: true)

    assert_equal Valkey::RequestType::SPUBLISH, client.last_command.request_type
    # Signature is (message, channel); wire order is <channel> <message>.
    assert_equal %w[shard-chan hello], client.last_command.args
  end

  def test_publish_sharded_works_without_resp3
    client = RecordingClient.new(response: 0, protocol: nil, cluster_mode: true)

    client.publish("hello", "shard-chan", sharded: true)

    assert_equal Valkey::RequestType::SPUBLISH, client.last_command.request_type
    assert_equal %w[shard-chan hello], client.last_command.args
  end

  def test_ssubscribe_dispatches_sblocking_with_timeout
    client = RecordingClient.new(cluster_mode: true)

    client.ssubscribe("shard1", "shard2", timeout_ms: 2000)

    assert_equal Valkey::RequestType::SSUBSCRIBE_BLOCKING, client.last_command.request_type
    assert_equal %w[shard1 shard2 2000], client.last_command.args
  end

  def test_ssubscribe_defaults_to_indefinite_timeout
    client = RecordingClient.new(cluster_mode: true)

    client.ssubscribe("shard1")

    assert_equal %w[shard1 0], client.last_command.args
  end

  def test_ssubscribe_coerces_arguments_and_truncates_timeout
    client = RecordingClient.new(cluster_mode: true)

    client.ssubscribe(:shard1, 42, timeout_ms: 1500.6)

    assert_equal %w[shard1 42 1500], client.last_command.args
  end

  def test_ssubscribe_rounds_sub_millisecond_timeout_up
    client = RecordingClient.new(cluster_mode: true)

    client.ssubscribe("shard1", timeout_ms: 0.4)

    assert_equal %w[shard1 1], client.last_command.args
  end

  def test_ssubscribe_rejects_a_negative_timeout
    client = RecordingClient.new(cluster_mode: true)

    assert_raises(ArgumentError) { client.ssubscribe("shard1", timeout_ms: -1) }
    assert_empty client.sent_commands
  end

  def test_ssubscribe_without_channels_raises
    client = RecordingClient.new(cluster_mode: true)

    error = assert_raises(ArgumentError) { client.ssubscribe }

    assert_equal "No channels provided for subscription", error.message
    assert_empty client.sent_commands
  end

  def test_sunsubscribe_dispatches_sblocking_with_timeout
    client = RecordingClient.new(cluster_mode: true)

    client.sunsubscribe("shard1", timeout_ms: 3000)

    assert_equal Valkey::RequestType::SUNSUBSCRIBE_BLOCKING, client.last_command.request_type
    assert_equal %w[shard1 3000], client.last_command.args
  end

  def test_sunsubscribe_without_channels_targets_all
    client = RecordingClient.new(cluster_mode: true)

    client.sunsubscribe

    assert_equal Valkey::RequestType::SUNSUBSCRIBE_BLOCKING, client.last_command.request_type
    assert_equal %w[0], client.last_command.args
  end

  def test_lazy_sharded_verbs_dispatch_without_a_timeout_argument
    client = RecordingClient.new(cluster_mode: true)

    client.ssubscribe_lazy("shard1")
    client.sunsubscribe_lazy("shard1")

    expected = [
      [Valkey::RequestType::SSUBSCRIBE, %w[shard1]],
      [Valkey::RequestType::SUNSUBSCRIBE, %w[shard1]]
    ]

    assert_equal(expected, client.sent_commands.map { |command| [command.request_type, command.args] })
  end

  def test_sunsubscribe_lazy_without_channels_targets_all
    client = RecordingClient.new(cluster_mode: true)

    client.sunsubscribe_lazy

    assert_equal Valkey::RequestType::SUNSUBSCRIBE, client.last_command.request_type
    assert_empty client.last_command.args
  end

  def test_ssubscribe_lazy_without_channels_raises
    client = RecordingClient.new(cluster_mode: true)

    error = assert_raises(ArgumentError) { client.ssubscribe_lazy }

    assert_equal "No channels provided for subscription", error.message
    assert_empty client.sent_commands
  end

  def test_sharded_verbs_require_cluster_mode
    client = RecordingClient.new # standalone

    {
      ssubscribe: -> { client.ssubscribe("shard1") },
      sunsubscribe: -> { client.sunsubscribe },
      ssubscribe_lazy: -> { client.ssubscribe_lazy("shard1") },
      sunsubscribe_lazy: -> { client.sunsubscribe_lazy }
    }.each do |name, call|
      error = assert_raises(ArgumentError, "#{name} must require cluster mode") { call.call }
      assert_match(/cluster mode/, error.message)
    end

    assert_empty client.sent_commands
  end

  def test_sharded_publish_is_allowed_in_standalone
    # publish stays batchable and un-guarded; the core decides. It must not
    # raise the client-side cluster-mode ArgumentError.
    client = RecordingClient.new(response: 0) # standalone

    client.publish("hello", "shard-chan", sharded: true)

    assert_equal Valkey::RequestType::SPUBLISH, client.last_command.request_type
  end

  def test_pubsub_channels_without_pattern_sends_no_arguments
    client = RecordingClient.new(response: [])

    client.pubsub_channels

    assert_equal Valkey::RequestType::PUBSUB_CHANNELS, client.last_command.request_type
    assert_equal [], client.last_command.args
  end

  def test_pubsub_channels_with_pattern
    client = RecordingClient.new(response: [])

    client.pubsub_channels("news.*")

    assert_equal Valkey::RequestType::PUBSUB_CHANNELS, client.last_command.request_type
    assert_equal ["news.*"], client.last_command.args
  end

  def test_pubsub_shardchannels_without_pattern_sends_no_arguments
    client = RecordingClient.new(response: [])

    client.pubsub_shardchannels

    assert_equal Valkey::RequestType::PUBSUB_SHARD_CHANNELS, client.last_command.request_type
    assert_equal [], client.last_command.args
  end

  def test_pubsub_shardchannels_with_pattern
    client = RecordingClient.new(response: [])

    client.pubsub_shardchannels("shard.*")

    assert_equal Valkey::RequestType::PUBSUB_SHARD_CHANNELS, client.last_command.request_type
    assert_equal ["shard.*"], client.last_command.args
  end

  def test_pubsub_numpat
    client = RecordingClient.new(response: 3)

    assert_equal 3, client.pubsub_numpat
    assert_equal Valkey::RequestType::PUBSUB_NUM_PAT, client.last_command.request_type
    assert_equal [], client.last_command.args
  end

  def test_pubsub_numsub_with_zero_one_and_several_channels
    [[], ["a"], %w[a b c]].each do |channels|
      client = RecordingClient.new(response: [])

      client.pubsub_numsub(*channels)

      assert_equal Valkey::RequestType::PUBSUB_NUM_SUB, client.last_command.request_type
      assert_equal channels, client.last_command.args
    end
  end

  def test_pubsub_shardnumsub_with_zero_one_and_several_channels
    [[], ["a"], %w[a b c]].each do |channels|
      client = RecordingClient.new(response: [])

      client.pubsub_shardnumsub(*channels)

      assert_equal Valkey::RequestType::PUBSUB_SHARD_NUM_SUB, client.last_command.request_type
      assert_equal channels, client.last_command.args
    end
  end

  def test_numsub_channel_arguments_coerce_to_strings
    %i[pubsub_numsub pubsub_shardnumsub].each do |name|
      client = RecordingClient.new(response: [])

      client.public_send(name, :alerts, 42)

      assert_equal %w[alerts 42], client.last_command.args, "#{name} must coerce channel args via to_s"
    end
  end

  def test_numsub_conversion_normalizes_every_reply_shape
    replies = [
      ["a", 1, "b", 2],           # RESP2 flat array
      { "a" => 1, "b" => 2 },     # RESP3 map
      [["a", 1], ["b", 2]]        # array of pairs
    ]

    %i[pubsub_numsub pubsub_shardnumsub].each do |name|
      replies.each do |reply|
        client = RecordingClient.new(response: reply)

        assert_equal({ "a" => 1, "b" => 2 }, client.public_send(name, "a", "b"),
                     "#{name} must normalize #{reply.inspect}")
      end
    end
  end

  def test_numsub_conversion_coerces_string_counts_to_integers
    %i[pubsub_numsub pubsub_shardnumsub].each do |name|
      client = RecordingClient.new(response: %w[a 1])

      assert_equal({ "a" => 1 }, client.public_send(name, "a"))
    end
  end

  def test_numsub_conversion_maps_an_empty_reply_to_an_empty_hash
    %i[pubsub_numsub pubsub_shardnumsub].each do |name|
      [[], {}].each do |reply|
        client = RecordingClient.new(response: reply)

        assert_equal({}, client.public_send(name), "#{name} must map #{reply.inspect} to {}")
      end
    end
  end

  def test_introspection_works_without_resp3
    {
      pubsub_channels: [],
      pubsub_numpat: 0,
      pubsub_numsub: [],
      pubsub_shardchannels: [],
      pubsub_shardnumsub: [],
      get_subscriptions: ["desired", {}, "actual", {}]
    }.each do |name, response|
      client = RecordingClient.new(response: response, protocol: nil)

      client.public_send(name)

      refute_empty client.sent_commands, "#{name} must work without RESP3"
    end
  end

  def test_get_subscriptions_request
    client = RecordingClient.new(response: ["desired", {}, "actual", {}])

    client.get_subscriptions

    assert_equal Valkey::RequestType::GET_SUBSCRIPTIONS, client.last_command.request_type
    assert_equal [], client.last_command.args
  end

  def test_get_subscriptions_builds_a_state_with_symbol_keys
    reply = [
      "desired",
      { "Exact" => %w[news], "Pattern" => ["news.*"], "Sharded" => %w[shard1] },
      "actual",
      { "Exact" => %w[news], "Pattern" => [], "Sharded" => %w[shard1] }
    ]
    client = RecordingClient.new(response: reply)

    state = client.get_subscriptions

    assert_instance_of Valkey::Glide::PubSubState, state
    assert_equal({ exact: %w[news], pattern: ["news.*"], sharded: %w[shard1] }, state.desired_subscriptions)
    assert_equal({ exact: %w[news], pattern: [], sharded: %w[shard1] }, state.actual_subscriptions)
  end

  def test_get_subscriptions_standalone_reply_omits_sharded
    reply = [
      "desired", { "Exact" => %w[news], "Pattern" => ["news.*"] },
      "actual", { "Exact" => %w[news] }
    ]
    client = RecordingClient.new(response: reply)

    state = client.get_subscriptions

    refute state.desired_subscriptions.key?(:sharded)
    refute state.actual_subscriptions.key?(:sharded)
    refute state.actual_subscriptions.key?(:pattern)
  end

  def test_get_subscriptions_deduplicates_channels
    reply = [
      "desired", { "Exact" => %w[news news alerts] },
      "actual", { "Exact" => %w[news news] }
    ]
    client = RecordingClient.new(response: reply)

    state = client.get_subscriptions

    assert_equal %w[news alerts], state.desired_subscriptions[:exact]
    assert_equal %w[news], state.actual_subscriptions[:exact]
  end

  def test_get_subscriptions_accepts_flattened_payloads
    reply = [
      "desired", ["Exact", %w[news], "Pattern", ["news.*"]],
      "actual", ["Exact", %w[news]]
    ]
    client = RecordingClient.new(response: reply)

    state = client.get_subscriptions

    assert_equal({ exact: %w[news], pattern: ["news.*"] }, state.desired_subscriptions)
    assert_equal({ exact: %w[news] }, state.actual_subscriptions)
  end

  def test_get_subscriptions_rejects_a_malformed_reply
    malformed = [
      ["desired", {}],                                # too short
      ["desired", {}, "actual", {}, "extra"],         # too long
      "not an array",
      nil
    ]

    malformed.each do |reply|
      client = RecordingClient.new(response: reply)

      error = assert_raises(Valkey::CommandError, "reply #{reply.inspect} must be rejected") do
        client.get_subscriptions
      end
      assert_match(/Unexpected GET_SUBSCRIPTIONS response/, error.message)
    end
  end

  def test_pubsub_dispatches_each_subcommand_case_insensitively
    {
      channels: Valkey::RequestType::PUBSUB_CHANNELS,
      numpat: Valkey::RequestType::PUBSUB_NUM_PAT,
      numsub: Valkey::RequestType::PUBSUB_NUM_SUB,
      shardchannels: Valkey::RequestType::PUBSUB_SHARD_CHANNELS,
      shardnumsub: Valkey::RequestType::PUBSUB_SHARD_NUM_SUB
    }.each do |subcommand, request_type|
      spellings = [subcommand, subcommand.to_s, subcommand.to_s.upcase, subcommand.to_s.capitalize.to_sym]

      spellings.each do |spelling|
        client = RecordingClient.new(response: [])

        client.pubsub(spelling)

        assert_equal request_type, client.last_command.request_type, "pubsub(#{spelling.inspect})"
      end
    end
  end

  def test_pubsub_dispatch_handles_mixed_case_spellings
    client = RecordingClient.new(response: [])

    client.pubsub(:NumPat)
    client.pubsub("CHANNELS")

    assert_equal Valkey::RequestType::PUBSUB_NUM_PAT, client.sent_commands[0].request_type
    assert_equal Valkey::RequestType::PUBSUB_CHANNELS, client.sent_commands[1].request_type
  end

  def test_pubsub_dispatch_forwards_extra_arguments
    client = RecordingClient.new(response: [])

    client.pubsub(:channels, "pat*")
    client.pubsub(:numsub, "a", "b")
    client.pubsub(:shardchannels, "shard*")
    client.pubsub(:shardnumsub, "a")

    assert_equal ["pat*"], client.sent_commands[0].args
    assert_equal %w[a b], client.sent_commands[1].args
    assert_equal ["shard*"], client.sent_commands[2].args
    assert_equal ["a"], client.sent_commands[3].args
  end

  def test_pubsub_dispatch_rejects_an_unknown_subcommand
    client = RecordingClient.new(response: [])

    error = assert_raises(ArgumentError) { client.pubsub(:bogus) }

    assert_equal "Unknown PUBSUB subcommand: :bogus", error.message
    assert_empty client.sent_commands
  end

  # --- RESP3 requirement ---------------------------------------------------

  def test_subscription_methods_reject_a_non_resp3_protocol
    [nil, :resp2, "resp2", 2].each do |protocol|
      # Cluster mode so the sharded verbs clear their cluster-only guard and
      # reach the RESP3 check; the non-sharded verbs are unaffected by it.
      client = RecordingClient.new(protocol: protocol, cluster_mode: true)

      guarded_calls(client).each do |name, call|
        # Timeout so a missing guard fails the assertion instead of blocking in
        # get_pubsub_message forever.
        error = assert_raises(Valkey::Resp3RequiredError, "#{name} must reject protocol #{protocol.inspect}") do
          Timeout.timeout(2) { call.call }
        end
        assert_match(/RESP3/, error.message)
      end
    end
  end

  def test_subscription_methods_accept_every_resp3_spelling
    [:resp3, "resp3", 3].each do |protocol|
      client = RecordingClient.new(protocol: protocol, cluster_mode: true)

      client.subscribe("news")
      client.unsubscribe
      client.psubscribe("news.*")
      client.punsubscribe
      client.subscribe_lazy("news")
      client.unsubscribe_lazy
      client.psubscribe_lazy("news.*")
      client.punsubscribe_lazy
      client.ssubscribe("shard1")
      client.sunsubscribe
      client.ssubscribe_lazy("shard1")
      client.sunsubscribe_lazy

      assert_nil client.try_get_pubsub_message, "protocol #{protocol.inspect} must be accepted"
      assert_equal "hello", queued_message(client).message
    end
  end

  private

  def receiver_for(client)
    client.instance_variable_get(:@pubsub_receiver)
  end

  # Bound via reflection because the parser is private on the client.
  def parse_pubsub_configs
    @pubsub.method(:parse_pubsub_configs)
  end

  # get_pubsub_message blocks, so it is only called on a queue that already
  # holds one.
  def queued_message(client)
    enqueue(client, Valkey::Glide::PubSubMessage.new("hello", "news", nil))
    client.get_pubsub_message
  end

  def enqueue(client, message)
    receiver_for(client).instance_variable_get(:@message_queue).push(message)
  end

  def guarded_calls(client)
    {
      subscribe: -> { client.subscribe("news") },
      unsubscribe: -> { client.unsubscribe },
      psubscribe: -> { client.psubscribe("news.*") },
      punsubscribe: -> { client.punsubscribe },
      subscribe_lazy: -> { client.subscribe_lazy("news") },
      unsubscribe_lazy: -> { client.unsubscribe_lazy },
      psubscribe_lazy: -> { client.psubscribe_lazy("news.*") },
      punsubscribe_lazy: -> { client.punsubscribe_lazy },
      ssubscribe: -> { client.ssubscribe("shard1") },
      sunsubscribe: -> { client.sunsubscribe },
      ssubscribe_lazy: -> { client.ssubscribe_lazy("shard1") },
      sunsubscribe_lazy: -> { client.sunsubscribe_lazy },
      get_pubsub_message: -> { client.get_pubsub_message },
      try_get_pubsub_message: -> { client.try_get_pubsub_message }
    }
  end
end
