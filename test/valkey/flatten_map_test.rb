# frozen_string_literal: true

module ValkeyTests
  module FlattenMap
    # Verifies the MAP response type branch in convert_response:
    #   @flatten_map ? map.to_a.flatten(1) : map

    def flatten_client
      @flatten_client ||= begin
        address = Helper::Client.server_address
        Valkey.new(host: address[:host], port: address[:port], timeout: TIMEOUT, flatten_map: true)
      end
    end

    def teardown_flatten_client
      @flatten_client&.close
      @flatten_client = nil
    end

    # Hook into existing teardown
    def teardown
      teardown_flatten_client
      super
    end

    # --- Core flatten_map behavior ---

    def test_flatten_map_default_returns_hash
      result = r.hello
      assert_kind_of Hash, result
      assert %w[valkey redis].include?(result["server"]), "Expected server to be valkey or redis"
      assert_equal "standalone", result["mode"]
    end

    def test_flatten_map_true_returns_flat_array
      result = flatten_client.hello

      assert_kind_of Array, result
      server_idx = result.index("server")
      refute_nil server_idx, "Expected 'server' key in flattened array"
      assert %w[valkey redis].include?(result[server_idx + 1]), "Expected server value to be valkey or redis"

      mode_idx = result.index("mode")
      refute_nil mode_idx, "Expected 'mode' key in flattened array"
      assert_equal "standalone", result[mode_idx + 1]
    end

    # --- Commands with Hashify post-processing blocks ---
    # These must return correct results regardless of flatten_map

    def test_flatten_map_hgetall
      flatten_client.hset("_fm_hash", "a", "1", "b", "2")
      result = flatten_client.hgetall("_fm_hash")

      assert_kind_of Hash, result
      assert_equal({ "a" => "1", "b" => "2" }, result)
    ensure
      flatten_client.del("_fm_hash")
    end

    def test_flatten_map_config_get
      result = flatten_client.config_get("maxmemory")

      assert_kind_of Hash, result
      assert result.key?("maxmemory")
    end

    def test_flatten_map_xrange
      flatten_client.xadd("_fm_stream", { "f1" => "v1" }, id: "1-0")
      flatten_client.xadd("_fm_stream", { "f2" => "v2" }, id: "2-0")

      result = flatten_client.xrange("_fm_stream", "-", "+")
      assert_kind_of Array, result
      assert_equal 2, result.length
      assert_equal "1-0", result[0][0]
      assert_includes result[0][1].flatten, "f1"
    ensure
      flatten_client.del("_fm_stream")
    end

    def test_flatten_map_xrevrange
      flatten_client.xadd("_fm_stream2", { "f1" => "v1" }, id: "1-0")
      flatten_client.xadd("_fm_stream2", { "f2" => "v2" }, id: "2-0")

      result = flatten_client.xrevrange("_fm_stream2")
      assert_kind_of Array, result
      assert_equal 2, result.length
      assert_equal "2-0", result[0][0]
    ensure
      flatten_client.del("_fm_stream2")
    end

    def test_flatten_map_xread
      flatten_client.xadd("_fm_xread", { "k" => "v" }, id: "1-0")

      result = flatten_client.xread(["_fm_xread"], ["0"])
      assert_kind_of Hash, result
      assert result.key?("_fm_xread")
      assert_kind_of Array, result["_fm_xread"]
    ensure
      flatten_client.del("_fm_xread")
    end

    def test_flatten_map_hrandfield_with_values
      flatten_client.hset("_fm_hrand", "a", "1", "b", "2", "c", "3")

      result = flatten_client.hrandfield("_fm_hrand", 2, with_values: true)
      assert_kind_of Array, result
      assert_equal 2, result.length
      assert_equal 2, result[0].length
    ensure
      flatten_client.del("_fm_hrand")
    end
  end
end
