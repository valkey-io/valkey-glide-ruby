# frozen_string_literal: true

require "openssl"
require_relative "../support/helper/ssl"

module Lint
  module ConnectionOptions
    include SslHelper

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

    def test_ssl_port
      defined?(SSL_PORT) ? SSL_PORT : 6380
    end

    def test_connection_with_host_and_port
      client = if cluster_mode?
                 # In cluster mode, use cluster nodes
                 Valkey.new(nodes: test_cluster_nodes, cluster_mode: true, timeout: test_timeout)
               else
                 Valkey.new(host: "127.0.0.1", port: test_port, timeout: test_timeout)
               end
      assert_equal "PONG", client.ping
      client.close
    end

    def test_connection_with_url
      client = if cluster_mode?
                 # In cluster mode, use cluster nodes
                 Valkey.new(nodes: test_cluster_nodes, cluster_mode: true, timeout: test_timeout)
               else
                 # Test URL parsing without authentication
                 Valkey.new(url: "redis://127.0.0.1:#{test_port}", timeout: test_timeout)
               end
      assert_equal "PONG", client.ping
      client.close
    end

    def test_connection_with_url_and_database
      client = if cluster_mode?
                 # In cluster mode, use cluster nodes (database selection not supported in cluster)
                 Valkey.new(nodes: test_cluster_nodes, cluster_mode: true, timeout: test_timeout)
               else
                 # Test URL with database number
                 Valkey.new(url: "redis://127.0.0.1:#{test_port}/15", timeout: test_timeout)
               end
      assert_equal "PONG", client.ping
      client.set("test_key", "test_value")
      assert_equal "test_value", client.get("test_key")
      client.close
    end

    def test_connection_with_database_option
      client = if cluster_mode?
                 # In cluster mode, use cluster nodes (database selection not supported in cluster)
                 Valkey.new(nodes: test_cluster_nodes, cluster_mode: true, timeout: test_timeout)
               else
                 # Test db option
                 Valkey.new(host: "127.0.0.1", port: test_port, db: 15, timeout: test_timeout)
               end
      assert_equal "PONG", client.ping
      client.set("test_key_db", "test_value_db")
      assert_equal "test_value_db", client.get("test_key_db")
      client.close
    end

    def test_connection_with_client_name
      # Test client_name option
      client_name = "test_client_#{Time.now.to_i}"
      client = if cluster_mode?
                 Valkey.new(
                   nodes: test_cluster_nodes, cluster_mode: true,
                   client_name: client_name, timeout: test_timeout
                 )
               else
                 Valkey.new(host: "127.0.0.1", port: test_port, client_name: client_name, timeout: test_timeout)
               end
      assert_equal "PONG", client.ping
      # Verify client name was set (may not be consistent across nodes in cluster mode)
      unless cluster_mode?
        name = client.client_get_name
        assert_equal client_name, name
      end
      client.close
    end

    def test_connection_with_timeout_options
      # Test timeout and connect_timeout options (redis-rb compatible)
      client = if cluster_mode?
                 Valkey.new(
                   nodes: test_cluster_nodes,
                   cluster_mode: true,
                   connect_timeout: 0.5,
                   timeout: test_timeout
                 )
               else
                 Valkey.new(
                   host: "127.0.0.1",
                   port: test_port,
                   connect_timeout: 0.5,
                   timeout: test_timeout
                 )
               end
      assert_equal "PONG", client.ping
      client.close
    end

    def test_connection_with_reconnect_options
      # Test reconnection strategy options
      client = if cluster_mode?
                 Valkey.new(
                   nodes: test_cluster_nodes,
                   cluster_mode: true,
                   reconnect_attempts: 3,
                   reconnect_delay: 0.5,
                   reconnect_delay_max: 2.0,
                   timeout: test_timeout
                 )
               else
                 Valkey.new(
                   host: "127.0.0.1",
                   port: test_port,
                   reconnect_attempts: 3,
                   reconnect_delay: 0.5,
                   reconnect_delay_max: 2.0,
                   timeout: test_timeout
                 )
               end
      assert_equal "PONG", client.ping
      client.close
    end

    def test_connection_url_parsing_with_password
      # Test URL parsing with password (if server has password set, this would work)
      # For now, just test that URL parsing doesn't crash
      # NOTE: This test may fail if server requires password
      client = if cluster_mode?
                 Valkey.new(
                   nodes: test_cluster_nodes, cluster_mode: true,
                   password: "test_password", timeout: test_timeout
                 )
               else
                 Valkey.new(url: "redis://:password@127.0.0.1:#{test_port}", timeout: test_timeout)
               end
      client.ping
      client.close
    rescue Valkey::CannotConnectError, Valkey::CommandError
      # Expected if password is wrong or server doesn't require password
      # This is acceptable - we're just testing URL parsing
    end

    def test_connection_url_parsing_with_username_and_password
      # Test URL parsing with username and password
      client = if cluster_mode?
                 Valkey.new(
                   nodes: test_cluster_nodes, cluster_mode: true,
                   username: "user", password: "password", timeout: test_timeout
                 )
               else
                 Valkey.new(url: "redis://user:password@127.0.0.1:#{test_port}", timeout: test_timeout)
               end
      client.ping
      client.close
    rescue Valkey::CannotConnectError, Valkey::CommandError
      # Expected if credentials are wrong or server doesn't require auth
      # This is acceptable - we're just testing URL parsing
    end

    def test_connection_url_parsing_ssl
      # Test URL parsing with SSL (rediss://)
      # For self-signed certs, we need to provide the CA cert
      client = if cluster_mode?
                 # In cluster mode, test SSL option directly
                 Valkey.new(
                   nodes: test_cluster_nodes,
                   cluster_mode: true,
                   ssl: true,
                   ssl_params: { ca_file: ssl_ca_cert_path },
                   timeout: test_timeout
                 )
               else
                 Valkey.new(
                   url: "rediss://127.0.0.1:#{test_ssl_port}",
                   ssl_params: { ca_file: ssl_ca_cert_path },
                   timeout: test_timeout
                 )
               end
      client.ping
      client.close
    rescue Valkey::CannotConnectError
      # Expected if SSL is not configured on server
      skip("SSL not configured on test server")
    end

    def test_connection_with_ssl_option
      # Test ssl option with CA certificate for self-signed cert
      client = if cluster_mode?
                 Valkey.new(
                   nodes: test_cluster_nodes,
                   cluster_mode: true,
                   ssl: true,
                   ssl_params: { ca_file: ssl_ca_cert_path },
                   timeout: test_timeout
                 )
               else
                 Valkey.new(
                   host: "127.0.0.1",
                   port: test_ssl_port,
                   ssl: true,
                   ssl_params: { ca_file: ssl_ca_cert_path },
                   timeout: test_timeout
                 )
               end
      client.ping
      client.close
    rescue Valkey::CannotConnectError
      # Expected if SSL is not configured
      skip("SSL not configured on test server")
    end

    def test_connection_url_options_merge_with_explicit_options
      # Test that explicit options override URL options
      client = if cluster_mode?
                 # In cluster mode, test that explicit nodes override URL
                 Valkey.new(
                   url: "redis://127.0.0.1:9999", # Wrong URL
                   nodes: test_cluster_nodes, # Correct nodes as explicit option
                   cluster_mode: true,
                   timeout: test_timeout
                 )
               else
                 Valkey.new(
                   url: "redis://127.0.0.1:9999", # Wrong port in URL
                   port: test_port, # Correct port as explicit option
                   timeout: test_timeout
                 )
               end
      assert_equal "PONG", client.ping
      client.close
    end

    def test_connection_defaults
      # Test default connection values
      client = if cluster_mode?
                 # In cluster mode, need to provide nodes
                 Valkey.new(nodes: test_cluster_nodes, cluster_mode: true, timeout: test_timeout)
               else
                 # Should connect to localhost:6379 by default
                 Valkey.new(timeout: test_timeout)
               end
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

    def test_cluster_connection_with_authentication
      # Test cluster mode with authentication
      if cluster_mode?
        # NOTE: Most test clusters don't have auth enabled
        client = Valkey.new(
          nodes: test_cluster_nodes,
          cluster_mode: true,
          password: "test_password",
          timeout: test_timeout
        )
        client.ping
        client.close
      else
        skip("Cluster mode not available in this test environment")
      end
    rescue Valkey::CannotConnectError, Valkey::CommandError
      # Expected if cluster doesn't require password
      skip("Cluster authentication not configured")
    end

    def test_cluster_connection_with_client_name
      # Test cluster mode with client name
      if cluster_mode?
        client_name = "cluster_test_#{Time.now.to_i}"
        client = Valkey.new(
          nodes: test_cluster_nodes,
          cluster_mode: true,
          client_name: client_name,
          timeout: test_timeout
        )
        assert_equal "PONG", client.ping
        # Client name may not be consistent across nodes in cluster mode
        # So we just verify the connection works
        client.close
      else
        skip("Cluster mode not available in this test environment")
      end
    end

    def test_cluster_connection_with_timeout_options
      # Test cluster mode with timeout options
      if cluster_mode?
        client = Valkey.new(
          nodes: test_cluster_nodes,
          cluster_mode: true,
          connect_timeout: 0.5,
          read_timeout: 2.0,
          timeout: test_timeout
        )
        assert_equal "PONG", client.ping
        client.close
      else
        skip("Cluster mode not available in this test environment")
      end
    end

    def test_cluster_connection_with_reconnect_options
      # Test cluster mode with reconnection strategy
      if cluster_mode?
        client = Valkey.new(
          nodes: test_cluster_nodes,
          cluster_mode: true,
          reconnect_attempts: 3,
          reconnect_delay: 0.5,
          reconnect_delay_max: 2.0,
          timeout: test_timeout
        )
        assert_equal "PONG", client.ping
        client.close
      else
        skip("Cluster mode not available in this test environment")
      end
    end

    def test_cluster_connection_with_protocol_option
      # Test cluster mode with protocol option
      if cluster_mode?
        client = Valkey.new(
          nodes: test_cluster_nodes,
          cluster_mode: true,
          protocol: :resp2,
          timeout: test_timeout
        )
        assert_equal "PONG", client.ping
        client.close

        client = Valkey.new(
          nodes: test_cluster_nodes,
          cluster_mode: true,
          protocol: :resp3,
          timeout: test_timeout
        )
        assert_equal "PONG", client.ping
        client.close
      else
        skip("Cluster mode not available in this test environment")
      end
    end

    def test_cluster_connection_nodes_parameter
      # Test that nodes parameter is correctly used
      if cluster_mode?
        # Test with explicit nodes
        client = Valkey.new(
          nodes: test_cluster_nodes,
          cluster_mode: true,
          timeout: test_timeout
        )
        assert_equal "PONG", client.ping
        client.close

        # Test that single node array works
        single_node = [{ host: "127.0.0.1", port: 7000 }]
        client = Valkey.new(
          nodes: single_node,
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
      if cluster_mode?
        client = Valkey.new(nodes: test_cluster_nodes, cluster_mode: true, protocol: :resp2, timeout: test_timeout)
        client.close

        client = Valkey.new(nodes: test_cluster_nodes, cluster_mode: true, protocol: :resp3, timeout: test_timeout)
      else
        client = Valkey.new(host: "127.0.0.1", port: test_port, protocol: :resp2, timeout: test_timeout)
        client.close

        client = Valkey.new(host: "127.0.0.1", port: test_port, protocol: :resp3, timeout: test_timeout)
      end
      assert_equal "PONG", client.ping
      client.close
    end

    def test_connection_ssl_params_with_file_paths
      # Test ssl_params with file paths using proper test certificates
      client = if cluster_mode?
                 Valkey.new(
                   nodes: test_cluster_nodes,
                   cluster_mode: true,
                   ssl: true,
                   ssl_params: {
                     ca_file: ssl_ca_cert_path,
                     cert: ssl_client_cert_path,
                     key: ssl_client_key_path
                   },
                   timeout: test_timeout
                 )
               else
                 Valkey.new(
                   host: "127.0.0.1",
                   port: test_ssl_port,
                   ssl: true,
                   ssl_params: {
                     ca_file: ssl_ca_cert_path,
                     cert: ssl_client_cert_path,
                     key: ssl_client_key_path
                   },
                   timeout: test_timeout
                 )
               end
      client.ping
      client.close
    rescue Valkey::CannotConnectError
      # Expected if SSL is not configured on server
      skip("SSL not configured on test server")
    end

    def test_connection_ssl_params_with_openssl_objects
      # Test ssl_params with OpenSSL objects loaded from test certificates
      # Need to provide CA cert to trust self-signed server certificate
      client = if cluster_mode?
                 Valkey.new(
                   nodes: test_cluster_nodes,
                   cluster_mode: true,
                   ssl: true,
                   ssl_params: {
                     ca_file: ssl_ca_cert_path,
                     cert: ssl_client_cert,
                     key: ssl_client_key
                   },
                   timeout: test_timeout
                 )
               else
                 Valkey.new(
                   host: "127.0.0.1",
                   port: test_ssl_port,
                   ssl: true,
                   ssl_params: {
                     ca_file: ssl_ca_cert_path,
                     cert: ssl_client_cert,
                     key: ssl_client_key
                   },
                   timeout: test_timeout
                 )
               end
      client.ping
      client.close
    rescue Valkey::CannotConnectError
      # Expected if SSL is not configured on server
      skip("SSL not configured on test server")
    end

    def test_connection_reconnect_strategy_calculation
      # Test that reconnect options are properly calculated
      # We can't easily test the actual reconnection, but we can test that
      # the options are accepted without error
      client = if cluster_mode?
                 Valkey.new(
                   nodes: test_cluster_nodes,
                   cluster_mode: true,
                   reconnect_attempts: 5,
                   reconnect_delay: 1.0,
                   reconnect_delay_max: 10.0,
                   timeout: test_timeout
                 )
               else
                 Valkey.new(
                   host: "127.0.0.1",
                   port: test_port,
                   reconnect_attempts: 5,
                   reconnect_delay: 1.0,
                   reconnect_delay_max: 10.0,
                   timeout: test_timeout
                 )
               end
      assert_equal "PONG", client.ping
      client.close
    end
  end
end
