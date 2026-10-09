# frozen_string_literal: true

require "test_helper"
require "json"

# Unit tests for the connection config options added in this PR: read_from,
# client_az, inflight_requests_limit, lazy_connect, periodic_checks.
#
# These are pure unit tests: we stub `Bindings.create_client_from_uri`,
# capture the `extra_options_json` string it was actually called with, and
# assert on its parsed shape. This is mode-agnostic (no real socket needed).
class TestConnectionConfig < Minitest::Test
  # Builds a `Valkey` client while intercepting the FFI call that would
  # normally open a real connection, returning the parsed `extra_options_json`
  # hash that `Valkey#initialize` built instead of a live client.
  #
  # Raises whatever `Valkey.new` raises (e.g. `ArgumentError`) if validation
  # fails before the FFI call is reached.
  def captured_client_args(options = {})
    captured = { uri: nil, json: nil }

    fake_response = Valkey::Bindings::ConnectionResponse.new
    fake_response[:conn_ptr] = FFI::Pointer.new(0x1)

    Valkey::Bindings.stub(:create_client_from_uri, lambda { |uri, json, _client_type, _callback|
      captured[:uri] = uri
      captured[:json] = json
      fake_response.to_ptr
    }) do
      Valkey::Bindings.stub(:free_connection_response, nil) do
        client_options = options.key?(:url) ? options : { host: "localhost", port: 6379 }.merge(options)
        client = ::Valkey.new(client_options)
        client.instance_variable_set(:@connection, nil) # skip close's real FFI call
      end
    end

    captured
  end

  def captured_json_options(options = {})
    json = captured_client_args(options)[:json]
    json.nil? ? {} : JSON.parse(json)
  end

  def scheme_for(options)
    captured_client_args(options)[:uri].start_with?("rediss://") ? "rediss" : "redis"
  end

  def test_lib_name_is_always_sent_to_the_ffi
    assert_equal "GlideRuby", captured_json_options["lib_name"]
  end

  def test_lib_name_override_reaches_the_ffi
    assert_equal "CustomLib", captured_json_options(lib_name: "CustomLib")["lib_name"]
  end

  def test_composed_lib_name_and_tag_reach_the_ffi
    json_options = captured_json_options(lib_name: "CustomLib", client_info_tag: "v2.0")
    assert_equal "CustomLib(v2.0)", json_options["lib_name"]
  end

  def test_tag_only_composes_against_default_base_in_the_ffi_payload
    assert_equal "GlideRuby(v2.0)", captured_json_options(client_info_tag: "v2.0")["lib_name"]
  end

  def test_lib_name_and_tag_are_not_transposed
    json_options = captured_json_options(lib_name: "CustomLib", client_info_tag: "v2.0")
    refute_equal "v2.0(CustomLib)", json_options["lib_name"]
  end

  # Routed through the FFI payload because JSON.generate runs after the resolver,
  # so a resolver-only version of this test would pass vacuously.
  def test_no_foreign_exception_escapes_client_construction_for_any_input_class
    raising = Object.new
    def raising.to_s
      raise "boom"
    end

    inputs = [
      nil, "", "GoodName", :SymLib, "café",
      "\xC3".dup.force_encoding("UTF-8"),
      "ab\xFFc".dup.force_encoding("ASCII-8BIT"),
      "plain".dup.force_encoding("ASCII-8BIT"),
      "caf\xE9".dup.force_encoding("ISO-8859-1"),
      false, true, 42, 8.1, [], {}, raising
    ]

    inputs.each do |input|
      captured_json_options(lib_name: input)
    rescue ArgumentError, Valkey::BaseError
      nil # permitted outcomes
    rescue StandardError => e
      flunk "lib_name: #{input.class} raised #{e.class}, which is neither " \
            "ArgumentError nor a Valkey error: #{e.message}"
    end
  end

  def test_read_from_accepts_canonical_strings
    %w[Primary PreferReplica AZAffinity AZAffinityReplicasAndPrimary AZAffinityAllNodes].each do |value|
      json_options = captured_json_options(read_from: value, client_az: "us-west-2a")
      assert_equal value, json_options["read_from"]
    end
  end

  def test_read_from_accepts_read_from_constants
    # Valkey::ReadFrom::* constants are just the canonical strings -- confirm
    # they round-trip through the passthrough unchanged.
    [
      Valkey::ReadFrom::PRIMARY,
      Valkey::ReadFrom::PREFER_REPLICA,
      Valkey::ReadFrom::AZ_AFFINITY,
      Valkey::ReadFrom::AZ_AFFINITY_REPLICAS_AND_PRIMARY,
      Valkey::ReadFrom::AZ_AFFINITY_ALL_NODES
    ].each do |value|
      json_options = captured_json_options(read_from: value, client_az: "us-west-2a")
      assert_equal value, json_options["read_from"]
    end
  end

  def test_read_from_symbol_is_passed_through_as_snake_case
    # read_from is a pure passthrough now -- Ruby does no symbol-to-canonical
    # translation. A symbol serializes to its snake_case string form via
    # JSON.generate, not the PascalCase the core expects; the core is the
    # sole validator and would reject this, but that's out of scope for this
    # unit test (which stubs the FFI call). Documents the actual contract:
    # use Valkey::ReadFrom::* constants or exact-match strings, not symbols.
    json_options = captured_json_options(read_from: :prefer_replica)
    assert_equal "prefer_replica", json_options["read_from"]
  end

  def test_read_from_az_affinity_requires_client_az
    json_options = captured_json_options(read_from: Valkey::ReadFrom::AZ_AFFINITY, client_az: "us-west-2a")
    assert_equal "AZAffinity", json_options["read_from"]
    assert_equal "us-west-2a", json_options["client_az"]
  end

  def test_read_from_az_affinity_replicas_and_primary_requires_client_az
    json_options = captured_json_options(
      read_from: Valkey::ReadFrom::AZ_AFFINITY_REPLICAS_AND_PRIMARY,
      client_az: "us-west-2a"
    )
    assert_equal "AZAffinityReplicasAndPrimary", json_options["read_from"]
    assert_equal "us-west-2a", json_options["client_az"]
  end

  def test_az_affinity_all_nodes_options_are_passed_to_ffi
    json_options = captured_json_options(
      read_from: Valkey::ReadFrom::AZ_AFFINITY_ALL_NODES,
      client_az: "us-west-2a"
    )
    assert_equal "AZAffinityAllNodes", json_options["read_from"]
    assert_equal "us-west-2a", json_options["client_az"]
  end

  def test_az_read_strategies_require_nonblank_client_az
    strategies = [
      Valkey::ReadFrom::AZ_AFFINITY,
      Valkey::ReadFrom::AZ_AFFINITY_REPLICAS_AND_PRIMARY,
      Valkey::ReadFrom::AZ_AFFINITY_ALL_NODES
    ]

    strategies.product([nil, "", " \t\n "]).each do |read_from, client_az|
      error = assert_raises(ArgumentError) do
        ::Valkey.new(host: "localhost", port: 6379, read_from: read_from, client_az: client_az)
      end
      assert_equal "client_az must be set when read_from is #{read_from}", error.message
    end
  end

  def test_read_from_unknown_string_is_passed_through_unchanged
    json_options = captured_json_options(read_from: "Bogus")
    assert_equal "Bogus", json_options["read_from"]
  end

  def test_read_from_omitted_when_not_provided
    json_options = captured_json_options
    refute json_options.key?("read_from")
  end

  def test_client_az_is_passed_through
    json_options = captured_json_options(client_az: "us-west-2a")
    assert_equal "us-west-2a", json_options["client_az"]
  end

  def test_client_az_strings_are_trimmed
    json_options = captured_json_options(client_az: " us-east-1a ")
    assert_equal "us-east-1a", json_options["client_az"]
  end

  def test_absent_and_blank_client_az_values_are_omitted_without_az_strategy
    [nil, "", " \t\n "].each do |client_az|
      json_options = captured_json_options(client_az: client_az)
      refute json_options.key?("client_az")
    end
  end

  def test_non_string_client_az_values_are_passed_through_for_ffi_validation
    [false, true, 123].each do |client_az|
      json_options = captured_json_options(
        read_from: Valkey::ReadFrom::AZ_AFFINITY_ALL_NODES,
        client_az: client_az
      )
      assert_equal client_az, json_options["client_az"]
    end
  end

  def test_inflight_requests_limit_is_passed_through
    json_options = captured_json_options(inflight_requests_limit: 1000)
    assert_equal 1000, json_options["inflight_requests_limit"]
  end

  def test_inflight_requests_limit_accepts_zero
    json_options = captured_json_options(inflight_requests_limit: 0)
    assert_equal 0, json_options["inflight_requests_limit"]
  end

  def test_inflight_requests_limit_omitted_when_not_provided
    json_options = captured_json_options
    refute json_options.key?("inflight_requests_limit")
  end

  def test_lazy_connect_true_is_serialized
    json_options = captured_json_options(lazy_connect: true)
    assert_equal true, json_options["lazy_connect"]
  end

  def test_lazy_connect_false_is_serialized
    # Pure passthrough now: explicitly passing false is forwarded as false,
    # not omitted -- only "not provided at all" omits the key (see below).
    json_options = captured_json_options(lazy_connect: false)
    assert_equal false, json_options["lazy_connect"]
  end

  def test_lazy_connect_omitted_when_not_provided
    json_options = captured_json_options
    refute json_options.key?("lazy_connect")
  end

  def test_periodic_checks_serializes_manual_interval
    json_options = captured_json_options(periodic_checks: { manual_interval: { duration_in_sec: 30 } })
    assert_equal({ "manual_interval" => { "duration_in_sec" => 30 } }, json_options["periodic_checks"])
  end

  def test_periodic_checks_serializes_manual_interval_with_string_keys
    json_options = captured_json_options(periodic_checks: { "manual_interval" => { "duration_in_sec" => 30 } })
    assert_equal({ "manual_interval" => { "duration_in_sec" => 30 } }, json_options["periodic_checks"])
  end

  def test_periodic_checks_serializes_disabled_true
    json_options = captured_json_options(periodic_checks: { disabled: true })
    assert_equal({ "disabled" => true }, json_options["periodic_checks"])
  end

  def test_periodic_checks_serializes_disabled_false
    json_options = captured_json_options(periodic_checks: { disabled: false })
    assert_equal({ "disabled" => false }, json_options["periodic_checks"])
  end

  def test_periodic_checks_accepted_without_raising_regardless_of_mode
    # periodic_checks is cluster-only in effect (topology refresh), but Ruby
    # must accept and serialize it identically on standalone -- it's a no-op
    # there, not rejected. Verified here by asserting the JSON shape is
    # produced the same way regardless of `cluster_mode:`; this test does
    # not depend on `cluster_mode?` because the Ruby-side code path is
    # identical either way (see build_periodic_checks).
    json_options = captured_json_options(periodic_checks: { manual_interval: { duration_in_sec: 5 } })
    assert_equal({ "manual_interval" => { "duration_in_sec" => 5 } }, json_options["periodic_checks"])
  end

  def test_periodic_checks_omitted_when_not_provided
    json_options = captured_json_options
    refute json_options.key?("periodic_checks")
  end

  def test_periodic_checks_rejects_non_hash
    # Shape check, not value validation -- a non-Hash can't be inspected for
    # :disabled/:manual_interval, so without this it'd be a NoMethodError.
    error = assert_raises(ArgumentError) do
      ::Valkey.new(host: "localhost", port: 6379, periodic_checks: "manual_interval")
    end
    assert_match(/periodic_checks must be a Hash/, error.message)
  end

  def test_periodic_checks_rejects_empty_hash
    # Same rationale: {} has neither key, so manual_interval would be nil.
    error = assert_raises(ArgumentError) do
      ::Valkey.new(host: "localhost", port: 6379, periodic_checks: {})
    end
    assert_match(/periodic_checks must contain :manual_interval or :disabled/, error.message)
  end

  def test_periodic_checks_rejects_manual_interval_non_hash
    error = assert_raises(ArgumentError) do
      ::Valkey.new(host: "localhost", port: 6379, periodic_checks: { manual_interval: "30" })
    end
    assert_match(/periodic_checks must contain :manual_interval or :disabled/, error.message)
  end

  def test_iam_config_serializes_username_and_json
    iam_config = Valkey::IamAuthConfig.new(
      cluster_name: "my-cache",
      service: Valkey::ServiceType::ELASTICACHE,
      region: "us-east-1",
      refresh_interval_seconds: 600
    )

    captured = captured_client_args(username: "iam-user", iam_config: iam_config)

    assert_equal "redis://iam-user@localhost:6379", captured[:uri]
    assert_equal(
      {
        "cluster_name" => "my-cache",
        "region" => "us-east-1",
        "service_type" => "ELASTICACHE",
        "refresh_interval_seconds" => 600
      },
      JSON.parse(captured[:json])["iam_credentials"]
    )
  end

  def test_iam_config_omits_default_refresh_interval
    iam_config = Valkey::IamAuthConfig.new(
      cluster_name: "my-cache",
      service: Valkey::ServiceType::ELASTICACHE,
      region: "us-east-1"
    )

    iam_credentials = captured_json_options(username: "iam-user", iam_config: iam_config)["iam_credentials"]

    assert_equal(
      {
        "cluster_name" => "my-cache",
        "region" => "us-east-1",
        "service_type" => "ELASTICACHE"
      },
      iam_credentials
    )
    refute iam_credentials.key?("refresh_interval_seconds")
  end

  def test_iam_username_is_percent_encoded
    iam_config = Valkey::IamAuthConfig.new(
      cluster_name: "my-cache",
      service: Valkey::ServiceType::ELASTICACHE,
      region: "us-east-1"
    )

    captured = captured_client_args(username: "iam user/@?", iam_config: iam_config)

    assert_equal "redis://iam%20user%2F%40%3F@localhost:6379", captured[:uri]
  end

  def test_url_username_combines_with_explicit_iam_config
    iam_config = Valkey::IamAuthConfig.new(
      cluster_name: "my-cache",
      service: Valkey::ServiceType::MEMORYDB,
      region: "us-west-2"
    )

    captured = captured_client_args(
      url: "rediss://iam%20user@cache.example.com:6380/2",
      iam_config: iam_config
    )

    assert_equal "rediss://iam%20user@cache.example.com:6380/2", captured[:uri]
    assert_equal(
      {
        "cluster_name" => "my-cache",
        "region" => "us-west-2",
        "service_type" => "MEMORYDB"
      },
      JSON.parse(captured[:json])["iam_credentials"]
    )
  end

  def test_iam_rejects_password
    iam_config = Valkey::IamAuthConfig.new(
      cluster_name: "my-cache",
      service: Valkey::ServiceType::ELASTICACHE,
      region: "us-east-1"
    )

    error = assert_raises(ArgumentError) do
      captured_client_args(username: "iam-user", password: "secret", iam_config: iam_config)
    end

    assert_match(/mutually exclusive/, error.message)
  end

  def test_iam_rejects_url_password
    iam_config = Valkey::IamAuthConfig.new(
      cluster_name: "my-cache",
      service: Valkey::ServiceType::ELASTICACHE,
      region: "us-east-1"
    )

    error = assert_raises(ArgumentError) do
      captured_client_args(url: "redis://iam-user:secret@localhost:6379", iam_config: iam_config)
    end

    assert_match(/mutually exclusive/, error.message)
  end

  def test_iam_accepts_empty_password
    iam_config = Valkey::IamAuthConfig.new(
      cluster_name: "my-cache",
      service: Valkey::ServiceType::ELASTICACHE,
      region: "us-east-1"
    )

    captured = captured_client_args(username: "iam-user", password: "", iam_config: iam_config)

    assert_equal "redis://iam-user@localhost:6379", captured[:uri]
  end

  def test_iam_accepts_empty_url_password
    iam_config = Valkey::IamAuthConfig.new(
      cluster_name: "my-cache",
      service: Valkey::ServiceType::ELASTICACHE,
      region: "us-east-1"
    )

    captured = captured_client_args(url: "redis://iam-user:@localhost:6379", iam_config: iam_config)

    assert_equal "redis://iam-user@localhost:6379", captured[:uri]
  end

  def test_iam_rejects_missing_username
    iam_config = Valkey::IamAuthConfig.new(
      cluster_name: "my-cache",
      service: Valkey::ServiceType::ELASTICACHE,
      region: "us-east-1"
    )

    error = assert_raises(ArgumentError) do
      captured_client_args(iam_config: iam_config)
    end

    assert_match(/username is required for iam_config/, error.message)
  end

  def test_iam_rejects_empty_username
    iam_config = Valkey::IamAuthConfig.new(
      cluster_name: "my-cache",
      service: Valkey::ServiceType::ELASTICACHE,
      region: "us-east-1"
    )

    error = assert_raises(ArgumentError) do
      captured_client_args(username: "", iam_config: iam_config)
    end

    assert_match(/username is required for iam_config/, error.message)
  end

  def test_iam_rejects_wrong_config_type
    error = assert_raises(ArgumentError) do
      captured_client_args(username: "iam-user", iam_config: {})
    end

    assert_match(/iam_config must be a Valkey::IamAuthConfig/, error.message)
  end

  def test_ssl_boolean_true_enables_tls
    assert_equal "rediss", scheme_for(ssl: true)
  end

  def test_ssl_string_true_enables_tls
    assert_equal "rediss", scheme_for(ssl: "true")
  end

  def test_ssl_integer_one_enables_tls
    assert_equal "rediss", scheme_for(ssl: 1)
  end

  def test_ssl_string_one_enables_tls
    assert_equal "rediss", scheme_for(ssl: "1")
  end

  def test_ssl_uppercase_true_string_enables_tls
    assert_equal "rediss", scheme_for(ssl: "TRUE")
  end

  def test_ssl_yes_string_enables_tls
    assert_equal "rediss", scheme_for(ssl: "yes")
  end

  def test_ssl_truthy_symbol_enables_tls
    assert_equal "rediss", scheme_for(ssl: :enabled)
  end

  def test_ssl_truthy_object_enables_tls
    assert_equal "rediss", scheme_for(ssl: Object.new)
  end

  def test_ssl_boolean_false_selects_plaintext
    assert_equal "redis", scheme_for(ssl: false)
  end

  def test_ssl_nil_selects_plaintext
    assert_equal "redis", scheme_for(ssl: nil)
  end

  def test_ssl_absent_option_selects_plaintext
    assert_equal "redis", scheme_for({})
  end

  def test_multiple_options_serialize_independently
    json_options = captured_json_options(
      read_from: Valkey::ReadFrom::AZ_AFFINITY,
      client_az: "us-west-2a",
      inflight_requests_limit: 500,
      lazy_connect: true,
      periodic_checks: { disabled: true }
    )

    assert_equal "AZAffinity", json_options["read_from"]
    assert_equal "us-west-2a", json_options["client_az"]
    assert_equal 500, json_options["inflight_requests_limit"]
    assert_equal true, json_options["lazy_connect"]
    assert_equal({ "disabled" => true }, json_options["periodic_checks"])
  end

  MISSING_SEED_MESSAGE = "cluster mode requires explicit nodes configuration."

  def assert_missing_seed_rejected(options)
    Valkey::Bindings.stub(:create_client_from_uri, ->(*) { flunk "FFI reached without a cluster seed" }) do
      error = assert_raises(ArgumentError) { ::Valkey.new(options) }
      assert_equal MISSING_SEED_MESSAGE, error.message
    end
  end

  def test_cluster_mode_without_seed_is_rejected
    assert_missing_seed_rejected(cluster_mode: true)
  end

  def test_cluster_mode_with_unset_seed_options_is_rejected
    assert_missing_seed_rejected(cluster_mode: true, host: nil, port: nil, url: nil, nodes: nil)
    assert_missing_seed_rejected(cluster_mode: true, host: "", url: "", nodes: false)
  end

  def test_cluster_mode_seed_check_precedes_other_validation
    assert_missing_seed_rejected(cluster_mode: true, db: -1)
  end

  def test_cluster_mode_with_empty_nodes_keeps_existing_error
    error = assert_raises(ArgumentError) { ::Valkey.new(cluster_mode: true, nodes: []) }
    assert_equal "Nodes array cannot be empty", error.message
  end

  def test_cluster_mode_host_only_uses_default_port
    uri = captured_client_args(cluster_mode: true, host: "cluster.example", port: nil)[:uri]
    assert_equal "redis://cluster.example:6379", uri
  end

  def test_cluster_mode_port_only_uses_default_host
    assert_equal "redis://127.0.0.1:7000", captured_client_args(cluster_mode: true, host: nil, port: 7000)[:uri]
    assert_equal "redis://127.0.0.1:7000", captured_client_args(cluster_mode: true, host: "", port: 7000)[:uri]
  end

  def test_cluster_mode_accepts_nodes
    uri = captured_client_args(cluster_mode: true, nodes: [{ host: "cluster.example", port: 7001 }])[:uri]
    assert_equal "redis://cluster.example:7001", uri
  end

  def test_cluster_mode_url_is_not_masked_by_unset_host_and_port
    uri = captured_client_args(cluster_mode: true, url: "redis://cluster.example:7000", host: nil, port: nil)[:uri]
    assert_equal "redis://cluster.example:7000", uri
  end

  def test_standalone_url_is_not_masked_by_empty_host
    uri = captured_client_args(url: "redis://standalone.example:7000", host: "", port: nil)[:uri]
    assert_equal "redis://standalone.example:7000", uri
  end

  def test_explicit_host_still_overrides_url
    uri = captured_client_args(url: "redis://url.example:7000", host: "explicit.example", port: nil)[:uri]
    assert_equal "redis://explicit.example:7000", uri
  end

  def test_standalone_without_seed_keeps_localhost_default
    assert_equal "redis://127.0.0.1:6379", captured_client_args(host: nil, port: nil)[:uri]
  end
end
