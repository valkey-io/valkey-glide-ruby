# frozen_string_literal: true

require "test_helper"
require "tempfile"

# Comprehensive test suite for URI-based client creation
# Tests both basic functionality and edge cases/validation
# This implementation eliminates the Protobuf dependency
class TestURIConnection < Minitest::Test
  # ====================
  # BASIC FUNCTIONALITY
  # ====================

  def test_simple_connection
    client = Valkey.new(host: "localhost", port: 6379)
    assert_equal "PONG", client.ping
    client.close
  end

  def test_connection_defaults
    # Test that defaults work (localhost:6379)
    client = Valkey.new
    assert_equal "PONG", client.ping
    client.close
  end

  def test_connection_with_database
    client = Valkey.new(host: "localhost", port: 6379, db: 1)
    assert_equal "PONG", client.ping
    client.close
  end

  def test_connection_with_database_zero
    # Explicit db: 0 should work
    client = Valkey.new(host: "localhost", port: 6379, db: 0)
    assert_equal "PONG", client.ping
    client.close
  end

  # ====================
  # TIMEOUT OPTIONS
  # ====================

  def test_connection_with_timeout
    client = Valkey.new(
      host: "localhost",
      port: 6379,
      timeout: 10.0,
      connect_timeout: 5.0
    )
    assert_equal "PONG", client.ping
    client.close
  end

  def test_connection_with_only_request_timeout
    client = Valkey.new(
      host: "localhost",
      port: 6379,
      timeout: 10.0
    )
    assert_equal "PONG", client.ping
    client.close
  end

  def test_connection_with_only_connect_timeout
    client = Valkey.new(
      host: "localhost",
      port: 6379,
      connect_timeout: 5.0
    )
    assert_equal "PONG", client.ping
    client.close
  end

  def test_very_large_timeout
    # Very large timeout should be accepted
    client = Valkey.new(
      host: "localhost",
      port: 6379,
      timeout: 3600.0 # 1 hour
    )
    assert_equal "PONG", client.ping
    client.close
  end

  def test_very_small_timeout
    # Very small but positive timeout
    client = Valkey.new(
      host: "localhost",
      port: 6379,
      timeout: 0.001 # 1ms
    )
    assert_equal "PONG", client.ping
    client.close
  end

  # ====================
  # CLIENT NAMING
  # ====================

  def test_connection_with_client_name
    client = Valkey.new(
      host: "localhost",
      port: 6379,
      client_name: "test_client"
    )
    assert_equal "PONG", client.ping

    # Verify client name is set
    client_list = client.client_list
    assert(client_list.any? { |c| c["name"] == "test_client" })

    client.close
  end

  # ====================
  # URL-BASED CONNECTIONS
  # ====================

  def test_url_based_connection
    client = Valkey.new(url: "redis://localhost:6379/0")
    assert_equal "PONG", client.ping
    client.close
  end

  def test_url_with_database
    client = Valkey.new(url: "redis://localhost:6379/1")
    assert_equal "PONG", client.ping
    client.close
  end

  def test_url_without_database
    client = Valkey.new(url: "redis://localhost:6379")
    assert_equal "PONG", client.ping
    client.close
  end

  def test_url_with_password
    # Test URL parsing with password (connection may fail if auth not configured)

    client = Valkey.new(url: "redis://:password@localhost:6379", connect_timeout: 1.0)
    client.ping
    client.close
  rescue Valkey::CannotConnectError, Valkey::CommandError
    # Expected if password is wrong or server doesn't require auth
    # We're just testing that URL parsing doesn't crash
  end

  def test_url_with_username_and_password
    # Test URL parsing with username and password

    client = Valkey.new(url: "redis://user:password@localhost:6379", connect_timeout: 1.0)
    client.ping
    client.close
  rescue Valkey::CannotConnectError, Valkey::CommandError
    # Expected if credentials are wrong or server doesn't require auth
    # We're just testing that URL parsing doesn't crash
  end

  def test_url_options_merge_with_explicit_options
    # Explicit options should override URL options
    client = Valkey.new(
      url: "redis://localhost:9999/5", # Wrong port and database in URL
      port: 6379, # Correct port as explicit option
      db: 0 # Correct database as explicit option
    )
    assert_equal "PONG", client.ping
    client.close
  end

  # ====================
  # PROTOCOL SELECTION
  # ====================

  def test_connection_with_resp3_protocol
    client = Valkey.new(
      host: "localhost",
      port: 6379,
      protocol: :resp3
    )
    assert_equal "PONG", client.ping
    client.close
  end

  def test_connection_with_resp2_protocol
    client = Valkey.new(
      host: "localhost",
      port: 6379,
      protocol: :resp2
    )
    assert_equal "PONG", client.ping
    client.close
  end

  def test_connection_with_protocol_string
    # Test protocol as string
    client = Valkey.new(
      host: "localhost",
      port: 6379,
      protocol: "resp3"
    )
    assert_equal "PONG", client.ping
    client.close
  end

  def test_connection_with_protocol_number
    # Test protocol as number
    client = Valkey.new(
      host: "localhost",
      port: 6379,
      protocol: 3
    )
    assert_equal "PONG", client.ping
    client.close
  end

  # ====================
  # RECONNECTION STRATEGY
  # ====================

  def test_connection_with_reconnect_options
    client = Valkey.new(
      host: "localhost",
      port: 6379,
      reconnect_attempts: 3,
      reconnect_delay: 0.5,
      reconnect_delay_max: 2.0
    )
    assert_equal "PONG", client.ping
    client.close
  end

  def test_connection_with_complex_reconnect_strategy
    # Test with more complex reconnect strategy
    client = Valkey.new(
      host: "localhost",
      port: 6379,
      reconnect_attempts: 5,
      reconnect_delay: 1.0,
      reconnect_delay_max: 10.0
    )
    assert_equal "PONG", client.ping
    client.close
  end

  def test_zero_reconnect_attempts
    # Zero retries should be valid (no retries)
    client = Valkey.new(
      host: "localhost",
      port: 6379,
      reconnect_attempts: 0
    )
    assert_equal "PONG", client.ping
    client.close
  end

  # ====================
  # COMBINED OPTIONS
  # ====================

  def test_connection_with_all_options_combined
    # Test multiple options together
    client = Valkey.new(
      host: "localhost",
      port: 6379,
      db: 1,
      client_name: "comprehensive_test",
      timeout: 15.0,
      connect_timeout: 3.0,
      protocol: :resp3,
      reconnect_attempts: 3,
      reconnect_delay: 0.5,
      reconnect_delay_max: 2.0
    )
    assert_equal "PONG", client.ping
    client.close
  end

  # ====================
  # REDIS OPERATIONS
  # ====================

  def test_basic_operations_work_with_uri
    client = Valkey.new(host: "localhost", port: 6379)

    # SET/GET
    client.set("uri_test_key", "uri_test_value")
    assert_equal "uri_test_value", client.get("uri_test_key")

    # INCR
    client.del("uri_counter")
    assert_equal 1, client.incr("uri_counter")

    # HSET/HGET
    client.hset("uri_hash", "field1", "value1")
    assert_equal "value1", client.hget("uri_hash", "field1")

    # LPUSH/LRANGE
    client.del("uri_list")
    client.lpush("uri_list", "item1")
    client.lpush("uri_list", "item2")
    assert_equal %w[item2 item1], client.lrange("uri_list", 0, -1)

    # SADD/SMEMBERS
    client.del("uri_set")
    client.sadd("uri_set", "member1")
    client.sadd("uri_set", "member2")
    members = client.smembers("uri_set")
    assert_equal 2, members.size
    assert_includes members, "member1"
    assert_includes members, "member2"

    # Cleanup
    client.del("uri_test_key", "uri_counter", "uri_hash", "uri_list", "uri_set")

    client.close
  end

  def test_transaction_operations_work_with_uri
    # Test that transactions work with URI-based connections
    client = Valkey.new(host: "localhost", port: 6379)

    client.del("tx_counter")

    results = client.multi do |tx|
      tx.set("tx_counter", "0")
      tx.incr("tx_counter")
      tx.incr("tx_counter")
      tx.get("tx_counter")
    end

    assert_equal "OK", results[0]
    assert_equal 1, results[1]
    assert_equal 2, results[2]
    assert_equal "2", results[3]

    client.del("tx_counter")
    client.close
  end

  def test_pipelined_operations_work_with_uri
    # Test that pipelined operations work with URI-based connections
    client = Valkey.new(host: "localhost", port: 6379)

    client.del("pipe_key1", "pipe_key2")

    results = client.pipelined do |pipeline|
      pipeline.set("pipe_key1", "value1")
      pipeline.set("pipe_key2", "value2")
      pipeline.get("pipe_key1")
      pipeline.get("pipe_key2")
    end

    assert_equal "OK", results[0]
    assert_equal "OK", results[1]
    assert_equal "value1", results[2]
    assert_equal "value2", results[3]

    client.del("pipe_key1", "pipe_key2")
    client.close
  end

  # ====================
  # CONNECTION MANAGEMENT
  # ====================

  def test_multiple_connections_simultaneously
    # Test that multiple connections can be created simultaneously
    clients = []

    5.times do |i|
      clients << Valkey.new(
        host: "localhost",
        port: 6379,
        client_name: "test_client_#{i}"
      )
    end

    # Verify all clients work
    clients.each do |client|
      assert_equal "PONG", client.ping
    end

    # Close all clients
    clients.each(&:close)
  end

  def test_connection_reuse_after_close
    # Test that we can create a new connection after closing
    client = Valkey.new(host: "localhost", port: 6379)
    assert_equal "PONG", client.ping
    client.close

    # Create new connection
    client2 = Valkey.new(host: "localhost", port: 6379)
    assert_equal "PONG", client2.ping
    client2.close
  end

  def test_invalid_connection_raises_error
    assert_raises(Valkey::CannotConnectError) do
      Valkey.new(host: "invalid-host-that-does-not-exist", port: 9999, connect_timeout: 1.0)
    end
  end

  # ========================================
  # VALIDATION & EDGE CASES
  # ========================================

  # ====================
  # NODE VALIDATION
  # ====================

  def test_empty_nodes_array
    error = assert_raises(ArgumentError) do
      Valkey.new(nodes: [])
    end
    assert_match(/Nodes array cannot be empty/, error.message)
  end

  def test_nil_node_in_array
    error = assert_raises(ArgumentError) do
      Valkey.new(nodes: [nil])
    end
    assert_match(/First node cannot be nil/, error.message)
  end

  def test_node_with_nil_host
    error = assert_raises(ArgumentError) do
      Valkey.new(nodes: [{ host: nil, port: 6379 }])
    end
    assert_match(/Host cannot be nil/, error.message)
  end

  def test_node_with_nil_port
    error = assert_raises(ArgumentError) do
      Valkey.new(nodes: [{ host: "localhost", port: nil }])
    end
    assert_match(/Port cannot be nil/, error.message)
  end

  def test_node_with_string_port
    error = assert_raises(ArgumentError) do
      Valkey.new(nodes: [{ host: "localhost", port: "6379" }])
    end
    assert_match(/Port must be a number/, error.message)
  end

  def test_float_port_number
    # Port must be integer, not float
    error = assert_raises(ArgumentError) do
      Valkey.new(host: "localhost", port: 6379.5)
    end
    assert_match(/Port must be a number/, error.message)
  end

  # ====================
  # DATABASE ID VALIDATION
  # ====================

  def test_negative_database_id
    error = assert_raises(ArgumentError) do
      Valkey.new(host: "localhost", port: 6379, db: -1)
    end
    assert_match(/Database ID must be non-negative/, error.message)
  end

  def test_negative_database_id_large
    error = assert_raises(ArgumentError) do
      Valkey.new(host: "localhost", port: 6379, db: -999)
    end
    assert_match(/Database ID must be non-negative/, error.message)
  end

  def test_large_database_id
    # Large positive database ID should be accepted (server will validate)

    client = Valkey.new(host: "localhost", port: 6379, db: 999, connect_timeout: 1.0)
    client.ping
    client.close
  rescue Valkey::CannotConnectError, Valkey::CommandError
    # Expected if database doesn't exist on server or connection fails
    # The important thing is that the validation didn't reject it
    pass
  end

  # ====================
  # TIMEOUT VALIDATION
  # ====================

  def test_timeout_as_string
    error = assert_raises(ArgumentError) do
      Valkey.new(host: "localhost", port: 6379, timeout: "10")
    end
    assert_match(/Timeout must be a number/, error.message)
  end

  def test_timeout_as_nil
    # Explicit nil should use default
    client = Valkey.new(host: "localhost", port: 6379, timeout: nil)
    # Should fall back to default 5.0
    assert_equal "PONG", client.ping
    client.close
  end

  def test_zero_timeout
    error = assert_raises(ArgumentError) do
      Valkey.new(host: "localhost", port: 6379, timeout: 0)
    end
    assert_match(/Timeout must be positive/, error.message)
  end

  def test_negative_timeout
    error = assert_raises(ArgumentError) do
      Valkey.new(host: "localhost", port: 6379, timeout: -5.0)
    end
    assert_match(/Timeout must be positive/, error.message)
  end

  def test_connect_timeout_as_string
    error = assert_raises(ArgumentError) do
      Valkey.new(host: "localhost", port: 6379, connect_timeout: "5")
    end
    assert_match(/Connect timeout must be a number/, error.message)
  end

  def test_zero_connect_timeout
    error = assert_raises(ArgumentError) do
      Valkey.new(host: "localhost", port: 6379, connect_timeout: 0)
    end
    assert_match(/Connect timeout must be positive/, error.message)
  end

  def test_negative_connect_timeout
    error = assert_raises(ArgumentError) do
      Valkey.new(host: "localhost", port: 6379, connect_timeout: -1.0)
    end
    assert_match(/Connect timeout must be positive/, error.message)
  end

  # ====================
  # SSL/TLS FILE VALIDATION
  # ====================

  def test_ssl_with_nonexistent_ca_file
    error = assert_raises(ArgumentError) do
      Valkey.new(
        host: "localhost",
        port: 6379,
        ssl: true,
        ssl_params: { ca_file: "/nonexistent/path/ca.pem" }
      )
    end
    assert_match(/CA file does not exist/, error.message)
  end

  def test_ssl_with_nonexistent_cert_file
    error = assert_raises(ArgumentError) do
      Valkey.new(
        host: "localhost",
        port: 6379,
        ssl: true,
        ssl_params: { cert: "/nonexistent/path/cert.pem" }
      )
    end
    assert_match(/Cert file does not exist/, error.message)
  end

  def test_ssl_with_nonexistent_key_file
    error = assert_raises(ArgumentError) do
      Valkey.new(
        host: "localhost",
        port: 6379,
        ssl: true,
        ssl_params: { key: "/nonexistent/path/key.pem" }
      )
    end
    assert_match(/Key file does not exist/, error.message)
  end

  def test_ssl_with_nonexistent_ca_path
    error = assert_raises(ArgumentError) do
      Valkey.new(
        host: "localhost",
        port: 6379,
        ssl: true,
        ssl_params: { ca_path: "/nonexistent/directory" }
      )
    end
    assert_match(/CA path does not exist/, error.message)
  end

  def test_ssl_with_unreadable_file
    # Create a temporary file and remove read permissions
    Tempfile.create("test_cert") do |file|
      file.write("dummy cert")
      file.close
      File.chmod(0o000, file.path)

      begin
        error = assert_raises(ArgumentError) do
          Valkey.new(
            host: "localhost",
            port: 6379,
            ssl: true,
            ssl_params: { ca_file: file.path }
          )
        end
        assert_match(/CA file is not readable/, error.message)
      ensure
        File.chmod(0o644, file.path) # Restore permissions for cleanup
      end
    end
  end

  # ====================
  # RECONNECTION STRATEGY VALIDATION
  # ====================

  def test_reconnect_attempts_as_string
    error = assert_raises(ArgumentError) do
      Valkey.new(
        host: "localhost",
        port: 6379,
        reconnect_attempts: "3"
      )
    end
    assert_match(/Reconnect attempts must be an integer/, error.message)
  end

  def test_reconnect_attempts_as_float
    error = assert_raises(ArgumentError) do
      Valkey.new(
        host: "localhost",
        port: 6379,
        reconnect_attempts: 3.5
      )
    end
    assert_match(/Reconnect attempts must be an integer/, error.message)
  end

  def test_negative_reconnect_attempts
    error = assert_raises(ArgumentError) do
      Valkey.new(
        host: "localhost",
        port: 6379,
        reconnect_attempts: -1
      )
    end
    assert_match(/Reconnect attempts must be non-negative/, error.message)
  end

  def test_reconnect_delay_as_string
    error = assert_raises(ArgumentError) do
      Valkey.new(
        host: "localhost",
        port: 6379,
        reconnect_delay: "0.5"
      )
    end
    assert_match(/Reconnect delay must be a number/, error.message)
  end

  def test_zero_reconnect_delay
    error = assert_raises(ArgumentError) do
      Valkey.new(
        host: "localhost",
        port: 6379,
        reconnect_delay: 0
      )
    end
    assert_match(/Reconnect delay must be positive/, error.message)
  end

  def test_negative_reconnect_delay
    error = assert_raises(ArgumentError) do
      Valkey.new(
        host: "localhost",
        port: 6379,
        reconnect_delay: -0.5
      )
    end
    assert_match(/Reconnect delay must be positive/, error.message)
  end

  def test_reconnect_delay_max_as_string
    error = assert_raises(ArgumentError) do
      Valkey.new(
        host: "localhost",
        port: 6379,
        reconnect_delay: 0.5,
        reconnect_delay_max: "2.0"
      )
    end
    assert_match(/Reconnect delay max must be a number/, error.message)
  end

  def test_zero_reconnect_delay_max
    error = assert_raises(ArgumentError) do
      Valkey.new(
        host: "localhost",
        port: 6379,
        reconnect_delay: 0.5,
        reconnect_delay_max: 0
      )
    end
    assert_match(/Reconnect delay max must be positive/, error.message)
  end

  def test_negative_reconnect_delay_max
    error = assert_raises(ArgumentError) do
      Valkey.new(
        host: "localhost",
        port: 6379,
        reconnect_delay: 0.5,
        reconnect_delay_max: -2.0
      )
    end
    assert_match(/Reconnect delay max must be positive/, error.message)
  end

  # ====================
  # SPECIAL CHARACTERS
  # ====================

  def test_password_with_special_characters
    # Test that special characters are properly URL-encoded
    special_passwords = [
      "p@ssword",
      "pass:word",
      "pass/word",
      "pass word",
      "p@ss:w/rd #test",
      "пароль", # Unicode
      "密码" # Unicode
    ]

    special_passwords.each do |password|
      # Connection will fail without auth, but URL should be properly encoded
      client = Valkey.new(
        host: "localhost",
        port: 6379,
        password: password,
        connect_timeout: 1.0
      )
      client.ping
      client.close
    rescue Valkey::CannotConnectError, Valkey::CommandError
      # Expected if server doesn't require this password
      # The important thing is it didn't crash during URI building
    end
  end

  def test_username_with_special_characters
    # Test that username is properly URL-encoded

    client = Valkey.new(
      host: "localhost",
      port: 6379,
      username: "user@domain",
      password: "p@ss:word",
      connect_timeout: 1.0
    )
    client.ping
    client.close
  rescue Valkey::CannotConnectError, Valkey::CommandError
    # Expected - we're just testing URL encoding
  end

  def test_empty_password
    # Empty password should be handled

    client = Valkey.new(
      host: "localhost",
      port: 6379,
      password: "",
      connect_timeout: 1.0
    )
    client.ping
    client.close
  rescue Valkey::CannotConnectError, Valkey::CommandError
    # Expected
  end

  # ====================
  # CLUSTER MODE
  # ====================

  def test_cluster_mode_with_single_node
    # Cluster mode with single node should work (server will handle discovery)

    client = Valkey.new(
      nodes: [{ host: "localhost", port: 7000 }],
      cluster_mode: true,
      connect_timeout: 1.0
    )
    client.ping
    client.close
  rescue Valkey::CannotConnectError
    # Expected if no cluster on port 7000
  end

  def test_cluster_mode_with_multiple_nodes
    # Multiple nodes should add addresses to JSON

    client = Valkey.new(
      nodes: [
        { host: "localhost", port: 7000 },
        { host: "localhost", port: 7001 },
        { host: "localhost", port: 7002 }
      ],
      cluster_mode: true,
      connect_timeout: 1.0
    )
    client.ping
    client.close
  rescue Valkey::CannotConnectError
    # Expected if no cluster
  end

  # ====================
  # COMBINED EDGE CASES
  # ====================

  def test_multiple_invalid_options
    # Test multiple validation errors - first one should be caught
    error = assert_raises(ArgumentError) do
      Valkey.new(
        host: "localhost",
        port: 6379,
        db: -1,
        timeout: "invalid",
        reconnect_attempts: -5
      )
    end
    # First validation error (db) should be raised
    assert_match(/Database ID must be non-negative/, error.message)
  end

  def test_url_with_invalid_scheme
    # redis-rb's parse_redis_url should handle this
    # but we should not crash

    Valkey.new(url: "http://localhost:6379", connect_timeout: 1.0)
  rescue ArgumentError, Valkey::CannotConnectError
    # Expected - invalid scheme
  end

  def test_url_overridden_by_explicit_invalid_values
    # Even if URL is valid, explicit invalid values should error
    error = assert_raises(ArgumentError) do
      Valkey.new(
        url: "redis://localhost:6379",
        db: -1 # Invalid explicit option
      )
    end
    assert_match(/Database ID must be non-negative/, error.message)
  end
end
