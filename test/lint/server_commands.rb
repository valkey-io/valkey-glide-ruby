# frozen_string_literal: true

module Lint
  module ServerCommands
    def test_bgrewriteaof
      skip("BGREWRITEAOF command not implemented in backend yet")

      response = r.bgrewriteaof
      assert_equal "OK", response
    end

    def test_bgsave
      skip("BGREWRITEAOF command not implemented in backend yet")

      response = r.bgsave
      assert_equal "Background saving started", response
    end

    def test_dbsize_flushdb
      r.set("key_0", "value_0")
      r.flushdb
      assert_equal 0, r.dbsize

      r.set("key_1", "value_1")
      r.set("key_2", "value_2")
      assert_equal 2, r.dbsize
    end

    def test_time
      result = r.time

      assert_kind_of Array, result
      assert_equal 2, result.size

      # convert to Ruby Time and assert it's close to now
      now = Time.now.to_f
      valkey_time = result[0].to_i + result[1].to_i / 1_000_000.0

      assert_in_delta now, valkey_time, 5.0 # within 5 seconds of system time
    end

    def test_lastsave_save
      before = r.lastsave
      assert_kind_of Integer, before
      assert_operator before, :>, 0

      skip("SAVE command not implemented in backend yet")
      r.set("test:lastsave", "123")
      r.save

      after = r.lastsave
      assert_kind_of Integer, after
      assert_operator after, :>=, before
    end

    def test_slaveof
      skip("SLAVEOF not implemented in backend yet")

      # Change this to a real Valkey/Redis master IP & port if available in test env
      host = "127.0.0.1"
      port = 6379

      response = r.slaveof(host, port)
      assert_equal "OK", response
    end

    def test_sync
      skip("SYNC command not implemented in backend yet")

      response = r.sync
      # The response can be nil or specific based on backend implementation
      assert response.nil? || response.is_a?(String), "Expected sync to return nil or a String"
    end

    def test_debug
      skip("DEBUG command not implemented in backend yet")

      r.set("somekey", "somevalue") # Ensure key exists
      response = r.debug("OBJECT", "somekey")
      assert response.is_a?(String), "Expected debug to return a String response"
    end

    def test_config_set
      response = r.config(:set, "maxmemory", "100mb")
      assert_equal "OK", response
    end

    def test_config_get
      r.config(:set, "maxmemory", "100mb")
      result = r.config(:get, "maxmemory")
      assert_kind_of Hash, result
      assert result.key?("maxmemory"), "Expected key 'maxmemory' in result"
      assert_equal "104857600", result["maxmemory"] # 100mb in bytes
    end

    def test_config_resetstat
      response = r.config(:resetstat)
      assert_equal "OK", response
    end

    def test_config_rewrite
      assert_raises(Valkey::CommandError, "Rewriting config file: Read-only file system") do
        r.config(:rewrite)
      end
    end

    def test_config_invalid
      assert_raises(NoMethodError) do
        r.config(:nonexistent)
      end
    end

    def test_client_id
      assert_kind_of Integer, r.client(:id)
    end

    def test_client_set_get_name
      r.client(:set_name, "test_client")
      assert_equal "test_client", r.client(:get_name)

      # Reset to default name
      r.client(:set_name, "")
      assert_nil r.client(:get_name)
    end

    def test_client_list
      response = r.client(:list)
      assert_kind_of Array, response
      assert response.all? { |client| client.is_a?(Hash) }, "Expected all clients to be represented as Hashes"
    end

    def test_client_pause_unpause
      assert_equal "OK", r.client(:pause, 100) # Pause for 100 milliseconds
      sleep(0.2)
      assert_equal "OK", r.client(:unpause)
    end

    def test_client_info
      response = r.client(:info)
      assert_kind_of String, response
      assert response.include?("id"), "Expected client info to contain 'id'"
      assert response.include?("name"), "Expected client info to contain 'name'"
    end

    def test_client_set_info
      assert_equal "OK", r.client(:set_info, 'lib-name', 'valkey') # TODO: 'implementing lib-var'
      assert_raises(Valkey::CommandError) do
        r.client(:set_info, 'foo', '0.0.1')
      end
    end

    def test_client_unblock
      result = r.client(:unblock, r.client(:id))
      assert [0, 1].include?(result), "Expected unblock to return 0 or 1"
    end

    def test_client_caching
      skip("CLIENT CACHING command not implemented in backend yet")

      # Assuming caching is enabled by default, this should return true
      response = r.client(:caching)
      assert_equal true, response
    end

    def test_client_tracking
      skip("CLIENT TRACKING command not implemented in backend yet")

      # Assuming tracking is enabled by default, this should return true
      response = r.client(:tracking)
      assert_equal true, response
    end

    def test_client_reply
      assert_equal "OK", r.client(:reply, "ON") # TODO: "OFF" or "SKIP" doesnt work yet
    end

    def test_client_kill
      # Create a second client connection
      extra_client = Valkey.new
      sleep(0.5) # Ensure the new client created

      addr = extra_client.client(:info)[/addr=(\S+)/, 1]

      if addr
        result = extra_client.client(:kill, addr)
        assert_equal "OK", result
      else
        skip("No client address found for extra client")
      end
    end

    def test_client_kill_simple
      extra_client = Valkey.new
      sleep(0.5) # Give it a moment to register with the server

      addr = extra_client.client(:info)[/addr=(\S+)/, 1]

      if addr
        result = extra_client.client(:kill_simple, addr)
        assert_equal "OK", result
      else
        skip("No client address found to kill")
      end
    end

    def test_client_tracking_info
      skip("CLIENT TRACKING command not implemented in backend yet")

      assert_kind_of Array, r.client(:tracking_info)
    end

    def test_client_getredir
      # extra_client = Valkey.new
      # extra_client.client('tracking', 'on', 'bcast') # TODO: Ensure tracking is implemented
      assert_kind_of Integer, r.client(:getredir)
    end

    def test_client_no_evict
      assert_equal "OK", r.client_no_evict(:on)
      assert_equal "OK", r.client_no_evict(:off)
      assert_raises(Valkey::CommandError) do
        r.client_no_evict(:xyz)
      end
    end

    def test_client_no_touch
      assert_equal "OK", r.client_no_touch(:on)
      assert_equal "OK", r.client_no_touch(:off)
      assert_raises(Valkey::CommandError) do
        r.client_no_touch(:xyz)
      end
    end
  end
end
