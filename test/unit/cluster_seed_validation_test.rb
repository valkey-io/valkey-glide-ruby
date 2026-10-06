# frozen_string_literal: true

require "test_helper"

# Covers cluster seed validation without opening network connections.
class TestClusterSeedValidation < Minitest::Test
  ERROR_MESSAGE = "`cluster_mode: true` requires seed nodes. " \
                  "Pass `host:`/`port:`, `url:`, or `nodes:`."

  def captured_client_args(options = {})
    captured = { uri: nil, json: nil }
    fake_response = Valkey::Bindings::ConnectionResponse.new
    fake_response[:conn_ptr] = FFI::Pointer.new(0x1)

    Valkey::Bindings.stub(:create_client_from_uri, lambda { |uri, json, _client_type, _callback|
      captured[:uri] = uri
      captured[:json] = JSON.parse(json)
      fake_response.to_ptr
    }) do
      Valkey::Bindings.stub(:free_connection_response, nil) do
        client = Valkey.new(options)
        client.instance_variable_set(:@connection, nil)
      end
    end

    captured
  end

  def assert_missing_seed_rejected(options)
    ffi_call = lambda do |*_arguments|
      raise "FFI reached with synthesized default seed"
    end

    Valkey::Bindings.stub(:create_client_from_uri, ffi_call) do
      error = assert_raises(Valkey::InvalidClientOptionError) do
        Valkey.new(options)
      end

      assert_equal ERROR_MESSAGE, error.message
    end
  end

  def test_cluster_mode_without_seed_options_raises_before_ffi
    assert_missing_seed_rejected(cluster_mode: true)
  end

  def test_cluster_mode_with_nil_seed_options_raises_before_ffi
    assert_missing_seed_rejected(
      cluster_mode: true,
      host: nil,
      port: nil,
      url: nil,
      nodes: nil
    )
  end

  def test_cluster_mode_with_empty_host_raises_before_ffi
    assert_missing_seed_rejected(cluster_mode: true, host: "")
  end

  def test_cluster_mode_with_empty_url_raises_before_ffi
    assert_missing_seed_rejected(cluster_mode: true, url: "")
  end

  def test_cluster_mode_with_nil_nodes_raises_before_ffi
    assert_missing_seed_rejected(cluster_mode: true, nodes: nil)
  end

  def test_cluster_mode_with_false_nodes_raises_before_ffi
    assert_missing_seed_rejected(cluster_mode: true, nodes: false)
  end

  def test_missing_seed_validation_precedes_other_option_validation
    assert_missing_seed_rejected(cluster_mode: true, db: -1)
  end

  def test_cluster_mode_with_tls_but_no_seed_raises_before_ffi
    assert_missing_seed_rejected(
      cluster_mode: true,
      ssl: true,
      ssl_params: { ca_path: "/path/that/does/not/exist" }
    )
  end

  def test_cluster_mode_with_lazy_connect_but_no_seed_raises_before_ffi
    assert_missing_seed_rejected(cluster_mode: true, lazy_connect: true)
  end

  def test_empty_nodes_keeps_existing_error
    error = assert_raises(ArgumentError) do
      Valkey.new(cluster_mode: true, nodes: [])
    end

    assert_equal "Nodes array cannot be empty", error.message
  end

  def test_cluster_mode_accepts_host_only_with_default_port
    captured = captured_client_args(cluster_mode: true, host: "cluster.example")

    assert_equal "redis://cluster.example:6379", captured[:uri]
  end

  def test_cluster_mode_accepts_port_only_with_default_host
    captured = captured_client_args(cluster_mode: true, port: 7000)

    assert_equal "redis://127.0.0.1:7000", captured[:uri]
  end

  def test_cluster_mode_treats_empty_host_with_port_as_port_only
    captured = captured_client_args(cluster_mode: true, host: "", port: 7000)

    assert_equal "redis://127.0.0.1:7000", captured[:uri]
  end

  def test_cluster_mode_accepts_url
    captured = captured_client_args(cluster_mode: true, url: "redis://cluster.example:7000")

    assert_equal "redis://cluster.example:7000", captured[:uri]
  end

  def test_cluster_mode_accepts_nodes
    captured = captured_client_args(
      cluster_mode: true,
      nodes: [{ host: "cluster.example", port: 7001 }]
    )

    assert_equal "redis://cluster.example:7001", captured[:uri]
  end

  def test_standalone_without_seed_options_keeps_default
    captured = captured_client_args

    assert_equal "redis://127.0.0.1:6379", captured[:uri]
  end

  def test_cluster_mode_with_seed_accepts_tls
    captured = captured_client_args(cluster_mode: true, host: "cluster.example", ssl: true)

    assert_equal "rediss://cluster.example:6379", captured[:uri]
  end

  def test_cluster_mode_with_seed_accepts_lazy_connect
    captured = captured_client_args(cluster_mode: true, host: "cluster.example", lazy_connect: true)

    assert_equal true, captured[:json]["lazy_connect"]
  end
end
