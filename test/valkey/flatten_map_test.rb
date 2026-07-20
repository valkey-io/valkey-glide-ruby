# frozen_string_literal: true

module ValkeyTests
  module FlattenMap
    # Verifies the MAP response type branch in convert_response:
    #   @flatten_map ? map.to_a.flatten(1) : map
    # Uses HELLO (returns MAP from glide-core) as representative command.

    def test_flatten_map_default_returns_hash
      address = Helper::Client.server_address
      client = Valkey.new(host: address[:host], port: address[:port], timeout: TIMEOUT)
      result = client.hello
      assert_kind_of Hash, result
      assert %w[valkey redis].include?(result["server"]), "Expected server to be valkey or redis"
      assert_equal "standalone", result["mode"]
    ensure
      client&.close
    end

    def test_flatten_map_true_returns_flat_array
      address = Helper::Client.server_address
      client = Valkey.new(host: address[:host], port: address[:port], timeout: TIMEOUT, flatten_map: true)
      result = client.hello

      assert_kind_of Array, result
      server_idx = result.index("server")
      refute_nil server_idx, "Expected 'server' key in flattened array"
      assert %w[valkey redis].include?(result[server_idx + 1]), "Expected server value to be valkey or redis"

      mode_idx = result.index("mode")
      refute_nil mode_idx, "Expected 'mode' key in flattened array"
      assert_equal "standalone", result[mode_idx + 1]
    ensure
      client&.close
    end
  end
end
