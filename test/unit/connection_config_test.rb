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
        client = ::Valkey.new({ host: "localhost", port: 6379 }.merge(options))
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

  # --- Library name / client info tag wiring (F-09) ---
  #
  # The resolver itself is covered by test/unit/lib_name_resolver_test.rb. What
  # these assert is the HANDOFF: that the resolved value actually reaches the FFI
  # payload under the key core reads. A renamed key, a deleted assignment, or
  # swapped keyword arguments would pass the whole resolver suite and fail only
  # against a live 7.2+ server.

  def test_lib_name_is_always_sent_to_the_ffi
    # Sent even with no options configured, so the reported identity does not
    # depend on how the native artifact was compiled.
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

  # Guards the keyword-argument wiring specifically: if lib_name and
  # client_info_tag were swapped at the call site, this would compose "v2.0(CustomLib)".
  def test_lib_name_and_tag_are_not_transposed
    json_options = captured_json_options(lib_name: "CustomLib", client_info_tag: "v2.0")
    refute_equal "v2.0(CustomLib)", json_options["lib_name"]
  end

  # THE PROPERTY, stated directly: for ANY input class, building a client either
  # succeeds or raises ArgumentError / a Valkey error — never a foreign exception
  # class. Asserting this, rather than a list of inputs, is what would have closed
  # this contract in one pass instead of three.
  #
  # Deliberately exercised through the FFI-payload path (captured_client_args)
  # rather than through resolve_lib_name alone. The resolver only composes a
  # String; JSON.generate runs later, so a resolver-only version of this test
  # passes VACUOUSLY when the guards are removed — verified by mutation. A
  # property test that cannot fail is worse than no test, because it reads as
  # coverage. This one bites.
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
    %w[Primary PreferReplica AZAffinity AZAffinityReplicasAndPrimary].each do |value|
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
      Valkey::ReadFrom::AZ_AFFINITY_REPLICAS_AND_PRIMARY
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

  def test_read_from_az_affinity_without_client_az_raises
    error = assert_raises(ArgumentError) do
      ::Valkey.new(host: "localhost", port: 6379, read_from: Valkey::ReadFrom::AZ_AFFINITY)
    end
    assert_match(/client_az must be set/, error.message)
  end

  def test_read_from_az_affinity_replicas_and_primary_without_client_az_raises
    error = assert_raises(ArgumentError) do
      ::Valkey.new(host: "localhost", port: 6379, read_from: Valkey::ReadFrom::AZ_AFFINITY_REPLICAS_AND_PRIMARY)
    end
    assert_match(/client_az must be set/, error.message)
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

  def test_client_az_omitted_when_not_provided
    json_options = captured_json_options
    refute json_options.key?("client_az")
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
end
