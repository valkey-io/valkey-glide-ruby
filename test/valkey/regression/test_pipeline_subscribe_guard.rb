# frozen_string_literal: true

require "test_helper"

# Regression: pipelined { |p| p.subscribe(...) } used to silently accept the
# subscribe command, send it through the batch, and leave the shared connection
# stuck in subscribe-state — every subsequent normal command then failed with
# "only (P|S)SUBSCRIBE / ... allowed in this context" and the block callback
# was never invoked.
#
# The Pipeline now rejects SUBSCRIBE-shape commands at send_command time,
# before any FFI dispatch, so callers see an actionable error and the client
# stays fully usable.
class TestPipelineSubscribeGuard < Minitest::Test
  ENDPOINT = if ENV["STANDALONE_ENDPOINTS"] && !ENV["STANDALONE_ENDPOINTS"].empty?
               host, port = ENV["STANDALONE_ENDPOINTS"].strip.rpartition(":").then { |p| [p[0], p[2]] }
               { host: host, port: port.to_i }
             else
               { host: "127.0.0.1", port: Integer(ENV["VALKEY_PORT"] || 6379) }
             end

  def setup
    @client = Valkey.new(host: ENDPOINT[:host], port: ENDPOINT[:port], timeout: 5.0)
  end

  def teardown
    @client&.close
  rescue StandardError
    # best-effort cleanup
  end

  # 1) subscribe inside pipelined raises before any FFI dispatch.
  def test_pipelined_subscribe_raises_command_error
    error = assert_raises(Valkey::CommandError) do
      @client.pipelined do |p|
        p.subscribe("ch") { |on| on.message { |_, _| next } }
      end
    end
    assert_match(/SUBSCRIBE-shape commands cannot be used inside pipelined/, error.message)
  end

  # 2) psubscribe inside pipelined is also rejected.
  def test_pipelined_psubscribe_raises_command_error
    assert_raises(Valkey::CommandError) do
      @client.pipelined do |p|
        p.psubscribe("ch.*") { |on| on.pmessage { |_, _, _| next } }
      end
    end
  end

  # 3) ssubscribe inside pipelined is also rejected (skip if the wrapper is
  #    missing on this client — some deployments do not expose ssubscribe).
  def test_pipelined_ssubscribe_raises_command_error
    skip "ssubscribe not defined on Pipeline" unless Valkey::Pipeline.method_defined?(:ssubscribe)
    assert_raises(Valkey::CommandError) do
      @client.pipelined do |p|
        p.ssubscribe("ch") { |on| on.smessage { |_, _| next } }
      end
    end
  end

  # 3b) unsubscribe / punsubscribe / sunsubscribe are also banned. These share
  # the same connection-state hazard as the subscribe variants.
  def test_pipelined_unsubscribe_variants_raise_command_error
    assert_raises(Valkey::CommandError) do
      @client.pipelined { |p| p.unsubscribe("ch") }
    end
    assert_raises(Valkey::CommandError) do
      @client.pipelined { |p| p.punsubscribe("ch.*") }
    end
    return unless Valkey::Pipeline.method_defined?(:sunsubscribe)

    assert_raises(Valkey::CommandError) do
      @client.pipelined { |p| p.sunsubscribe("ch") }
    end
  end

  # 3c) multi { |m| m.subscribe(...) } also uses Pipeline internally, so the
  # same guard fires — subscribe in a transaction would strand the connection
  # the same way it does in a plain pipeline.
  def test_multi_subscribe_raises_command_error
    assert_raises(Valkey::CommandError) do
      @client.multi do |m|
        m.subscribe("ch") { |on| on.message { |_, _| next } }
      end
    end
  end

  # 4) After a rejected pipelined subscribe, the same client remains fully
  #    usable — the guard fires before any FFI dispatch touches the connection.
  def test_client_remains_usable_after_rejected_pipelined_subscribe
    assert_raises(Valkey::CommandError) do
      @client.pipelined do |p|
        p.subscribe("ch") { |on| on.message { |_, _| next } }
      end
    end

    @client.set("regression:pipeline-subscribe-guard", "ok")
    assert_equal "ok", @client.get("regression:pipeline-subscribe-guard")
    assert_equal "PONG", @client.ping
    @client.del("regression:pipeline-subscribe-guard")
  end

  # 5) The guard is pipeline-only: calling subscribe directly on the client
  #    does not raise the guard's Valkey::CommandError. We verify by looking
  #    for the guard's own error message — anything else means the guard did
  #    not fire on the direct client-level subscribe path.
  def test_client_subscribe_does_not_trigger_pipeline_guard
    subscribe_error = nil
    begin
      @client.subscribe("regression:pipeline-guard:direct") do |on|
        on.subscribe do |_, _|
          # Immediately unsubscribe to let the block return cleanly.
          @client.unsubscribe("regression:pipeline-guard:direct")
        end
      end
    rescue Valkey::CommandError => e
      subscribe_error = e
    end

    return unless subscribe_error

    refute_match(
      /SUBSCRIBE-shape commands cannot be used inside pipelined/,
      subscribe_error.message,
      "pipeline guard fired on direct-client subscribe path"
    )
  end
end
