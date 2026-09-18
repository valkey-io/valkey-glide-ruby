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

  def test_pubsub_commands_raise_argument_error
    pipeline = Valkey::Pipeline.new

    Valkey::Pipeline::PUBSUB_UNSUPPORTED.each do |name|
      error = assert_raises(ArgumentError, "#{name} must be rejected") { pipeline.public_send(name) }

      assert_equal "#{name} is not supported inside pipelined/multi", error.message
    end
  end

  def test_sharded_subscribe_verbs_are_unsupported_in_a_pipeline
    %i[ssubscribe sunsubscribe ssubscribe_lazy sunsubscribe_lazy].each do |name|
      assert_includes Valkey::Pipeline::PUBSUB_UNSUPPORTED, name
    end
  end

  def test_publish_is_batchable_including_sharded
    pipeline = Valkey::Pipeline.new

    plain = pipeline.publish("hello", "news")
    sharded = pipeline.publish("hello", "shard-chan", sharded: true)

    assert_instance_of Valkey::Future, plain
    assert_instance_of Valkey::Future, sharded
    assert_equal [
      [Valkey::RequestType::PUBLISH, %w[news hello], nil],
      [Valkey::RequestType::SPUBLISH, %w[shard-chan hello], nil]
    ], pipeline.commands
  end
end
