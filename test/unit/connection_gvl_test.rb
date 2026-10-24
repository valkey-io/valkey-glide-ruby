# frozen_string_literal: true

require "test_helper"
require "socket"

# Regression test for issue #309: `Valkey.new` must release the GVL while the
# native `create_client_from_uri` call waits on the network, so unrelated Ruby
# threads keep running. Runs without a Valkey server: a local TCP listener
# completes the TCP handshake but never answers, so the native connect blocks
# until `connect_timeout` expires.
class TestConnectionGvlUnit < Minitest::Test
  def test_client_creation_releases_gvl_while_connecting
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    ticks = 0
    running = true
    ticker = Thread.new do
      while running
        ticks += 1
        sleep 0.005
      end
    end
    sleep 0.05 # let the ticker start

    ticks_before = ticks
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(Valkey::CannotConnectError) do
      Valkey.new(host: "127.0.0.1", port: port, connect_timeout: 0.5, timeout: 0.5)
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    ticks_during = ticks - ticks_before

    assert_operator elapsed, :>=, 0.2, "native connect returned too fast (#{elapsed}s) to observe GVL behaviour"
    assert_operator ticks_during, :>=, 10,
                    "only #{ticks_during} ticker iterations ran during a #{elapsed.round(2)}s connect; " \
                    "create_client_from_uri appears to hold the GVL"
  ensure
    running = false
    ticker&.join
    server&.close
  end
end
