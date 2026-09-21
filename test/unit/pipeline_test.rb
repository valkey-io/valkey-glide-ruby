# frozen_string_literal: true

require "test_helper"

# Unit tests for Valkey::Pipeline's Future bookkeeping.
# These do not require a running server — they test the Ruby layer only.
class TestPipelineUnit < Minitest::Test
  def test_send_command_returns_a_future_and_queues_the_command
    pipeline = Valkey::Pipeline.new

    future = pipeline.send_command(Valkey::RequestType::GET, ["foo"])

    assert_instance_of Valkey::Future, future
    assert_equal [[Valkey::RequestType::GET, ["foo"], nil]], pipeline.commands
    assert_equal [future], pipeline.futures
  end

  def test_resolve_futures_sets_each_future_by_position
    pipeline = Valkey::Pipeline.new

    future_a = pipeline.send_command(Valkey::RequestType::SET, %w[foo bar])
    future_b = pipeline.send_command(Valkey::RequestType::GET, ["foo"])
    future_c = pipeline.send_command(Valkey::RequestType::INCR, ["counter"])

    pipeline.resolve_futures!(["OK", "bar", 5])

    assert_equal "OK", future_a.value
    assert_equal "bar", future_b.value
    assert_equal 5, future_c.value
  end

  def test_abort_futures_marks_only_unresolved_futures
    pipeline = Valkey::Pipeline.new

    future_a = pipeline.send_command(Valkey::RequestType::SET, %w[foo bar])
    future_b = pipeline.send_command(Valkey::RequestType::GET, ["foo"])

    future_a._set("OK")
    pipeline.abort_futures!

    assert_equal "OK", future_a.value
    assert_raises(Valkey::FutureAborted) { future_b.value }
  end

  def test_pipeline_not_supported_pubsub
    pipeline = Valkey::Pipeline.new

    not_supported = %i[
      subscribe unsubscribe psubscribe punsubscribe ssubscribe sunsubscribe
      subscribe_lazy unsubscribe_lazy psubscribe_lazy punsubscribe_lazy
      ssubscribe_lazy sunsubscribe_lazy
      get_subscriptions get_pubsub_message try_get_pubsub_message
    ].freeze

    not_supported.each do |name|
      error = assert_raises(ArgumentError, "#{name} must be rejected") { pipeline.public_send(name) }

      assert_equal "#{name} is not supported inside pipelined/multi", error.message
    end
  end

  def test_sharded_subscribe_verbs_are_unsupported_in_a_pipeline
    %i[ssubscribe sunsubscribe ssubscribe_lazy sunsubscribe_lazy].each do |name|
      assert_includes Valkey::Pipeline::PUBSUB_UNSUPPORTED, name
    end
  end

  def test_sharded_pubsub_batch_commands_require_cluster_mode
    pipeline = Valkey::Pipeline.new
    calls = {
      publish: -> { pipeline.publish("hello", "shard-chan", sharded: true) },
      pubsub_shardchannels: -> { pipeline.pubsub_shardchannels },
      pubsub_shardnumsub: -> { pipeline.pubsub_shardnumsub("shard-chan") }
    }

    calls.each do |name, call|
      error = assert_raises(ArgumentError, "#{name} must require cluster mode", &call)

      assert_match(/cluster mode/, error.message)
    end

    assert_empty pipeline.commands
    assert_empty pipeline.futures
  end

  def test_pubsub_batch_commands_queue_and_return_futures
    pipeline = Valkey::Pipeline.new(cluster_mode: true)

    futures = [
      pipeline.publish("hello", "news"),
      pipeline.pubsub_channels("news.*"),
      pipeline.pubsub_numpat,
      pipeline.pubsub_numsub("news", "alerts"),
      pipeline.publish("hello", "shard-chan", sharded: true),
      pipeline.pubsub_shardchannels("shard-*"),
      pipeline.pubsub_shardnumsub("shard-chan")
    ]

    futures.each { |future| assert_instance_of Valkey::Future, future }
    assert_equal futures, pipeline.futures
    assert_equal [
      [Valkey::RequestType::PUBLISH, %w[news hello], nil],
      [Valkey::RequestType::PUBSUB_CHANNELS, ["news.*"], nil],
      [Valkey::RequestType::PUBSUB_NUM_PAT, [], nil],
      [Valkey::RequestType::PUBSUB_NUM_SUB, %w[news alerts], nil],
      [Valkey::RequestType::SPUBLISH, %w[shard-chan hello], nil],
      [Valkey::RequestType::PUBSUB_SHARD_CHANNELS, ["shard-*"], nil],
      [Valkey::RequestType::PUBSUB_SHARD_NUM_SUB, ["shard-chan"], nil]
    ], pipeline.commands
  end

  def test_get_subscriptions_is_not_batchable
    pipeline = Valkey::Pipeline.new

    error = assert_raises(ArgumentError) { pipeline.get_subscriptions }

    assert_equal "get_subscriptions is not supported inside pipelined/multi", error.message
    assert_empty pipeline.commands
    assert_empty pipeline.futures
  end
end
