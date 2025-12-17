# frozen_string_literal: true

module Lint
  module ConnectionCommands
    def test_ping_without_message
      assert_equal "PONG", r.ping
    end

    def test_ping_with_message
      message = "Hello World"
      assert_equal message, r.ping(message)
    end

    def test_echo
      message = "Hello Valkey"
      assert_equal message, r.echo(message)
    end

    def test_auth_no_password
      # Test auth when no password is set - should raise error
      assert_raises(Valkey::CommandError) do
        r.auth("some_password")
      end
    end

    def test_select_database
      assert_equal "OK", r.select(0)
      # In cluster mode, only database 0 is supported
      if cluster_mode?
        assert_raises(Valkey::CommandError) do
          r.select(1)
        end
      else
        assert_equal "OK", r.select(1)
        assert_equal "OK", r.select(0) # Switch back to default
      end
    end

    def test_client_id
      # Use the server commands interface that's known to work
      assert_kind_of Integer, r.client(:id)
    end

    def test_client_set_get_name
      name = "lint_test_client"
      # Use the server commands interface that's known to work
      r.client(:set_name, name)
      assert_equal name, r.client(:get_name)
      # Clear client name
      r.client(:set_name, "")
      assert_nil r.client(:get_name)
    end

    def test_client_list
      # Use the server commands interface that's known to work
      list = r.client(:list)
      assert_kind_of Array, list
      assert list.all? { |client| client.is_a?(Hash) }, "Expected all clients to be represented as Hashes"
    end

    def test_client_info
      # Use the server commands interface that's known to work
      info = r.client(:info)
      assert_kind_of String, info
      assert info.include?("id="), "Client info should contain client ID"
    end

    def test_client_pause_unpause
      # Pause for a short duration
      assert_equal "OK", r.client(:pause, 100) # 100ms pause

      # Wait for the pause to expire naturally before unpausing
      sleep(0.15) # Wait longer than pause duration

      # Now unpause should work without timing out
      assert_equal "OK", r.client(:unpause)
    end

    def test_client_reply
      # Use the server commands interface that's known to work
      assert_equal "OK", r.client(:reply, "ON")
    end

    def test_client_set_info
      target_version "7.2" do
        # Use the server commands interface that's known to work
        assert_equal "OK", r.client(:set_info, "lib-name", "valkey-ruby")
        assert_raises(Valkey::CommandError) do
          r.client(:set_info, "invalid-attr", "value")
        end
      end
    end

    def test_client_unblock
      # Use the server commands interface that's known to work
      client_id = r.client(:id)
      result = r.client(:unblock, client_id)
      assert [0, 1].include?(result), "Unblock should return 0 or 1"
    end

    def test_client_no_evict
      # Use the server commands interface that's known to work
      assert_equal "OK", r.client_no_evict(:on)
      assert_equal "OK", r.client_no_evict(:off)
      assert_raises(Valkey::CommandError) do
        r.client_no_evict(:invalid)
      end
    end

    def test_client_no_touch
      target_version "7.2" do
        # Use the server commands interface that's known to work
        assert_equal "OK", r.client_no_touch(:on)
        assert_equal "OK", r.client_no_touch(:off)
        assert_raises(Valkey::CommandError) do
          r.client_no_touch(:invalid)
        end
      end
    end

    def test_client_getredir
      redir = r.client_getredir
      assert_kind_of Integer, redir
    end

    def test_hello_default
      result = r.hello
      # Backend returns array in current implementation
      # TODO: Backend should convert RESP3 map to Ruby Hash
      assert_kind_of Array, result
      assert result.include?("server"), "HELLO response should contain server info"
    end

    def test_hello_with_version
      result = r.hello(3)
      # Backend returns array in current implementation
      # TODO: Backend should convert RESP3 map to Ruby Hash
      assert_kind_of Array, result
      proto_index = result.index("proto")
      assert_equal 3, result[proto_index + 1] if proto_index
    end

    def test_hello_with_setname
      client_name = "hello_lint_test"
      result = r.hello(3, setname: client_name)
      # Backend returns array in current implementation
      # TODO: Backend should convert RESP3 map to Ruby Hash
      assert_kind_of Array, result
      # In cluster mode, HELLO and CLIENT GETNAME might hit different nodes
      # so we can't reliably assert the name was set
      assert_equal client_name, r.client_get_name unless cluster_mode?
    end

    def test_reset
      # Set some state
      r.client_set_name("before_reset")
      # In cluster mode, we can only use database 0
      r.select(1) unless cluster_mode?
      # Reset
      result = r.reset
      assert_equal "RESET", result
      # In cluster mode, client state may not be consistent across nodes
      # so we skip the client name assertion
      return if cluster_mode?

      # State should be reset - retry with timeout to handle timing issues
      timeout = Time.now + 1.0 # 1 second timeout
      loop do
        name = r.client_get_name
        break if name.nil?

        raise "Timeout waiting for client name to reset" if Time.now > timeout

        sleep(0.05) # 50ms between retries
      end
      assert_nil r.client_get_name
    end

    def test_client_caching
      # In cluster mode, CLIENT TRACKING and CLIENT CACHING may hit different nodes
      # so tracking state isn't shared - skip this test in cluster mode
      skip("CLIENT CACHING requires tracking state to be shared, not reliable in cluster mode") if cluster_mode?

      # CLIENT CACHING YES works with OPTIN mode
      r.client_tracking("ON", "OPTIN")
      assert_equal "OK", r.client_caching("YES")
      r.client_tracking("OFF")
      # CLIENT CACHING NO requires OPTOUT mode
      r.client_tracking("ON", "OPTOUT")
      assert_equal "OK", r.client_caching("NO")
      r.client_tracking("OFF")
    end

    def test_client_tracking
      assert_equal "OK", r.client_tracking("ON")
      assert_equal "OK", r.client_tracking("OFF")
    end

    def test_client_tracking_info
      info = r.client_tracking_info
      assert_kind_of Array, info
    end

    def test_quit
      # NOTE: This test is tricky because QUIT closes the connection
      # We'll skip it in lint tests to avoid connection issues
      skip("QUIT command closes connection - tested separately")
    end
  end
end
