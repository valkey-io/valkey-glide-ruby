# frozen_string_literal: true

require "test_helper"

# Unit tests for Valkey::Future.
# These do not require a running server — they test the Ruby layer only.
class TestFutureUnit < Minitest::Test
  def test_value_raises_future_not_ready_before_resolution
    future = Valkey::Future.new(Valkey::RequestType::GET, ["foo"])

    assert_raises(Valkey::FutureNotReady) { future.value }
  end

  def test_ready_predicate_before_resolution
    future = Valkey::Future.new(Valkey::RequestType::GET, ["foo"])

    refute future.ready?
  end

  def test_value_returns_resolved_object_after_set
    future = Valkey::Future.new(Valkey::RequestType::GET, ["foo"])
    future._set("s1")

    assert future.ready?
    assert_equal "s1", future.value
  end

  def test_value_raises_the_resolved_command_error
    future = Valkey::Future.new(Valkey::RequestType::INCR, ["foo"])
    future._set(Valkey::CommandError.new("boom"))

    assert_raises(Valkey::CommandError) { future.value }
  end

  def test_value_raises_future_aborted_after_abort
    future = Valkey::Future.new(Valkey::RequestType::SET, %w[foo bar])
    future._abort!

    assert_raises(Valkey::FutureAborted) { future.value }
  end

  def test_future_aborted_is_a_future_not_ready
    assert Valkey::FutureAborted < Valkey::FutureNotReady
  end

  def test_abort_after_set_is_a_no_op
    future = Valkey::Future.new(Valkey::RequestType::GET, ["foo"])
    future._set("s1")
    future._abort!

    assert_equal "s1", future.value
  end

  def test_inspect_includes_command_type_and_args
    future = Valkey::Future.new(Valkey::RequestType::GET, ["foo"])

    assert_match(/Valkey::Future/, future.inspect)
    assert_match(/"foo"/, future.inspect)
  end
end
