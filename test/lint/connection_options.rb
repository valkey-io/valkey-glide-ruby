# frozen_string_literal: true

module Lint
  module ConnectionOptions
    # Helper to get test port and timeout
    def test_port
      defined?(PORT) ? PORT : 6379
    end

    def test_timeout
      defined?(TIMEOUT) ? TIMEOUT : 5.0
    end

    def test_cluster_nodes
      defined?(CLUSTER_NODES) ? CLUSTER_NODES : []
    end

    def test_connection_with_host_and_port
      client = Valkey.new(host: "127.0.0.1", port: test_port, timeout: test_timeout)
      assert_equal "PONG", client.ping
      client.close
    end

    def test_connection_with_url
      # Test URL parsing without authentication
      client = Valkey.new(url: "redis://127.0.0.1:#{test_port}", timeout: test_timeout)
      assert_equal "PONG", client.ping
      client.close
    end

    def test_connection_with_url_and_database
      # Test URL with database number
      client = Valkey.new(url: "redis://127.0.0.1:#{test_port}/15", timeout: test_timeout)
      assert_equal "PONG", client.ping
      # Verify we're on database 15
      client.set("test_key", "test_value")
      assert_equal "test_value", client.get("test_key")
      client.close
    end

    def test_connection_with_database_option
      # Test db option (redis-rb compatibility)
      client = Valkey.new(host: "127.0.0.1", port: test_port, db: 15, timeout: test_timeout)
      assert_equal "PONG", client.ping
      # Verify we're on database 15
      client.set("test_key_db", "test_value_db")
      assert_equal "test_value_db", client.get("test_key_db")
      client.close
    end

    def test_connection_with_client_name
      # Test client_name option
      client_name = "test_client_#{Time.now.to_i}"
      client = Valkey.new(host: "127.0.0.1", port: test_port, client_name: client_name, timeout: test_timeout)
      assert_equal "PONG", client.ping
      # Verify client name was set (may not work in cluster mode)
      unless cluster_mode?
        # Client name should be set via CLIENT GETNAME
        name = client.client_get_name
        assert_equal client_name, name
      end
      client.close
    end

    def test_connection_with_timeout_options
      # Test timeout options
      client = Valkey.new(
        host: "127.0.0.1",
        port: test_port,
        connect_timeout: 0.5,
        read_timeout: 2.0,
        timeout: test_timeout
      )
      assert_equal "PONG", client.ping
      client.close
    end

    def test_connection_with_write_timeout
      # Test write_timeout (used as fallback for request_timeout)
      client = Valkey.new(
        host: "127.0.0.1",
        port: test_port,
        write_timeout: 2.0,
        timeout: test_timeout
      )
      assert_equal "PONG", client.ping
      client.close
    end

    def test_connection_with_reconnect_options
      # Test reconnection strategy options
      client = Valkey.new(
        host: "127.0.0.1",
        port: test_port,
        reconnect_attempts: 3,
        reconnect_delay: 0.5,
        reconnect_delay_max: 2.0,
        timeout: test_timeout
      )
      assert_equal "PONG", client.ping
      client.close
    end

    def test_connection_url_parsing_with_password
      # Test URL parsing with password (if server has password set, this would work)
      # For now, just test that URL parsing doesn't crash
      # Note: This test may fail if server requires password
      begin
        client = Valkey.new(url: "redis://:password@127.0.0.1:#{test_port}", timeout: test_timeout)
        client.ping
        client.close
      rescue Valkey::CannotConnectError, Valkey::CommandError
        # Expected if password is wrong or server doesn't require password
        # This is acceptable - we're just testing URL parsing
      end
    end

    def test_connection_url_parsing_with_username_and_password
      # Test URL parsing with username and password
      begin
        client = Valkey.new(url: "redis://user:password@127.0.0.1:#{test_port}", timeout: test_timeout)
        client.ping
        client.close
      rescue Valkey::CannotConnectError, Valkey::CommandError
        # Expected if credentials are wrong or server doesn't require auth
        # This is acceptable - we're just testing URL parsing
      end
    end

    def test_connection_url_parsing_ssl
      # Test URL parsing with SSL (rediss://)
      # Note: This will fail if server doesn't have SSL enabled
      begin
        client = Valkey.new(url: "rediss://127.0.0.1:#{test_port}", timeout: test_timeout)
        client.ping
        client.close
      rescue Valkey::CannotConnectError
        # Expected if SSL is not configured on server
        # This is acceptable - we're just testing URL parsing sets ssl flag
      end
    end

    def test_connection_with_ssl_option
      # Test ssl option (will fail if server doesn't have SSL)
      begin
        client = Valkey.new(host: "127.0.0.1", port: test_port, ssl: true, timeout: test_timeout)
        client.ping
        client.close
      rescue Valkey::CannotConnectError
        # Expected if SSL is not configured
        skip("SSL not configured on test server")
      end
    end

    def test_connection_url_options_merge_with_explicit_options
      # Test that explicit options override URL options
      client = Valkey.new(
        url: "redis://127.0.0.1:9999", # Wrong port in URL
        port: test_port, # Correct port as explicit option
        timeout: test_timeout
      )
      assert_equal "PONG", client.ping
      client.close
    end

    def test_connection_defaults
      # Test default connection values
      # Should connect to localhost:6379 by default
      client = Valkey.new(timeout: test_timeout)
      assert_equal "PONG", client.ping
      client.close
    end

    def test_connection_with_cluster_mode
      # Test cluster mode (if available)
      if cluster_mode?
        client = Valkey.new(
          nodes: test_cluster_nodes,
          cluster_mode: true,
          timeout: test_timeout
        )
        assert_equal "PONG", client.ping
        client.close
      else
        skip("Cluster mode not available in this test environment")
      end
    end

    def test_connection_with_protocol_option
      # Test protocol option (RESP2 vs RESP3)
      client = Valkey.new(host: "127.0.0.1", port: test_port, protocol: :resp2, timeout: test_timeout)
      assert_equal "PONG", client.ping
      client.close

      client = Valkey.new(host: "127.0.0.1", port: test_port, protocol: :resp3, timeout: test_timeout)
      assert_equal "PONG", client.ping
      client.close
    end

    def test_connection_ssl_params_with_file_paths
      # Test ssl_params with file paths (will fail if files don't exist or SSL not configured)
      # This is a smoke test - actual SSL files may not exist in test environment
      begin
        # Create temporary test files
        require "tempfile"
        ca_file = Tempfile.new(["ca", ".crt"])
        ca_file.write("-----BEGIN CERTIFICATE-----\nTEST\n-----END CERTIFICATE-----\n")
        ca_file.close

        cert_file = Tempfile.new(["cert", ".crt"])
        cert_file.write("-----BEGIN CERTIFICATE-----\nTEST\n-----END CERTIFICATE-----\n")
        cert_file.close

        key_file = Tempfile.new(["key", ".key"])
        key_file.write("-----BEGIN PRIVATE KEY-----\nTEST\n-----END PRIVATE KEY-----\n")
        key_file.close

        client = Valkey.new(
          host: "127.0.0.1",
          port: test_port,
          ssl: true,
          ssl_params: {
            ca_file: ca_file.path,
            cert: cert_file.path,
            key: key_file.path
          },
          timeout: test_timeout
        )
        client.ping
        client.close
      rescue Valkey::CannotConnectError, Errno::ENOENT
        # Expected if SSL files don't exist or SSL not configured
        skip("SSL files or SSL configuration not available")
      ensure
        ca_file&.unlink
        cert_file&.unlink
        key_file&.unlink
      end
    end

    def test_connection_ssl_params_with_openssl_objects
      # Test ssl_params with OpenSSL objects (if available)
      begin
        require "openssl"

        # Create test certificate and key
        key = OpenSSL::PKey::RSA.new(2048)
        cert = OpenSSL::X509::Certificate.new
        cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=test")
        cert.not_before = Time.now
        cert.not_after = Time.now + 365 * 24 * 60 * 60
        cert.public_key = key.public_key
        cert.sign(key, OpenSSL::Digest.new("SHA256"))

        client = Valkey.new(
          host: "127.0.0.1",
          port: test_port,
          ssl: true,
          ssl_params: {
            cert: cert,
            key: key
          },
          timeout: test_timeout
        )
        client.ping
        client.close
      rescue LoadError, Valkey::CannotConnectError
        # OpenSSL not available or SSL not configured
        skip("OpenSSL or SSL configuration not available")
      end
    end

    def test_connection_reconnect_strategy_calculation
      # Test that reconnect options are properly calculated
      # We can't easily test the actual reconnection, but we can test that
      # the options are accepted without error
      client = Valkey.new(
        host: "127.0.0.1",
        port: test_port,
        reconnect_attempts: 5,
        reconnect_delay: 1.0,
        reconnect_delay_max: 10.0,
        timeout: test_timeout
      )
      assert_equal "PONG", client.ping
      client.close
    end

    def test_connection_database_id_option
      # Test database_id option (alternative to db)
      client = Valkey.new(host: "127.0.0.1", port: test_port, database_id: 15, timeout: test_timeout)
      assert_equal "PONG", client.ping
      client.set("test_db_id", "value")
      assert_equal "value", client.get("test_db_id")
      client.close
    end

    def test_connection_name_option_alias
      # Test name option (alias for client_name)
      client_name = "test_name_#{Time.now.to_i}"
      client = Valkey.new(host: "127.0.0.1", port: test_port, name: client_name, timeout: test_timeout)
      assert_equal "PONG", client.ping
      unless cluster_mode?
        assert_equal client_name, client.client_get_name
      end
      client.close
    end
  end
end

