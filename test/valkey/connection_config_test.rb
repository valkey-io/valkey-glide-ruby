# frozen_string_literal: true

require "json"

# Unit tests for the connection config options added in this PR: read_from,
# client_az, inflight_requests_limit, lazy_connect, periodic_checks.
#
# These are pure unit tests: instead of opening a real connection and asserting
# `PING` succeeds (which only proves the client didn't crash, not that the
# option was serialized correctly), we stub `Bindings.create_client_from_uri`,
# capture the `extra_options_json` string it was actually called with, and
# assert on its parsed shape. This is mode-agnostic (no real socket needed) and
# is included by both the standalone and cluster test classes via
# `Dir["valkey/**/*.rb"]` autoloading.
module ValkeyTests
  module ConnectionConfig
    # Builds a `Valkey` client while intercepting the FFI call that would
    # normally open a real connection, returning the parsed `extra_options_json`
    # hash that `Valkey#initialize` built instead of a live client.
    #
    # Raises whatever `Valkey.new` raises (e.g. `ArgumentError`) if validation
    # fails before the FFI call is reached.
    def captured_json_options(options = {})
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

      captured[:json].nil? ? {} : JSON.parse(captured[:json])
    end

    # NOTE: "LowestLatency" is a valid read_from value per the FFI docs
    # (ffi/src/lib.rs) and is accepted by Ruby's validation, but the currently
    # vendored glide-core build panics with `todo!()` when converting it
    # (glide-core/src/client/types.rs, `impl From<protobuf::ConnectionRequest>`,
    # reached via ffi/src/lib.rs's create_client_from_uri -> ConnectionRequest::from).
    # This is an upstream native-core gap, not a Ruby-side bug. Because these
    # tests stub the FFI call entirely, the panic can never actually be reached
    # here -- but the value is still listed for completeness of the
    # canonical-string/symbol mapping being verified.
    READ_FROM_JSON_VALUES = {
      "Primary" => :primary,
      "PreferReplica" => :prefer_replica,
      "LowestLatency" => :lowest_latency,
      "AZAffinity" => :az_affinity,
      "AZAffinityReplicasAndPrimary" => :az_affinity_replicas_and_primary
    }.freeze

    # ====================
    # read_from
    # ====================

    def test_read_from_accepts_canonical_strings
      READ_FROM_JSON_VALUES.each_key do |value|
        json_options = captured_json_options(read_from: value)
        assert_equal value, json_options["read_from"]
      end
    end

    def test_read_from_accepts_ruby_friendly_symbols
      READ_FROM_JSON_VALUES.each do |expected_string, symbol|
        json_options = captured_json_options(read_from: symbol)
        assert_equal expected_string, json_options["read_from"]
      end
    end

    def test_read_from_rejects_unknown_string
      error = assert_raises(ArgumentError) do
        ::Valkey.new(host: "localhost", port: 6379, read_from: "Bogus")
      end
      assert_match(/Invalid read_from value/, error.message)
    end

    def test_read_from_rejects_unknown_symbol
      error = assert_raises(ArgumentError) do
        ::Valkey.new(host: "localhost", port: 6379, read_from: :bogus)
      end
      assert_match(/Invalid read_from value/, error.message)
    end

    def test_read_from_omitted_when_not_provided
      json_options = captured_json_options
      refute json_options.key?("read_from")
    end

    # ====================
    # client_az
    # ====================

    def test_client_az_accepts_string
      json_options = captured_json_options(client_az: "us-west-2a")
      assert_equal "us-west-2a", json_options["client_az"]
    end

    def test_client_az_rejects_non_string
      error = assert_raises(ArgumentError) do
        ::Valkey.new(host: "localhost", port: 6379, client_az: 123)
      end
      assert_match(/client_az must be a string/, error.message)
    end

    def test_client_az_omitted_when_not_provided
      json_options = captured_json_options
      refute json_options.key?("client_az")
    end

    # ====================
    # inflight_requests_limit
    # ====================

    def test_inflight_requests_limit_accepts_positive_integer
      json_options = captured_json_options(inflight_requests_limit: 1000)
      assert_equal 1000, json_options["inflight_requests_limit"]
    end

    def test_inflight_requests_limit_accepts_zero
      json_options = captured_json_options(inflight_requests_limit: 0)
      assert_equal 0, json_options["inflight_requests_limit"]
    end

    def test_inflight_requests_limit_rejects_negative
      error = assert_raises(ArgumentError) do
        ::Valkey.new(host: "localhost", port: 6379, inflight_requests_limit: -1)
      end
      assert_match(/inflight_requests_limit must be non-negative/, error.message)
    end

    def test_inflight_requests_limit_rejects_non_integer
      error = assert_raises(ArgumentError) do
        ::Valkey.new(host: "localhost", port: 6379, inflight_requests_limit: "1000")
      end
      assert_match(/inflight_requests_limit must be an integer/, error.message)
    end

    def test_inflight_requests_limit_omitted_when_not_provided
      json_options = captured_json_options
      refute json_options.key?("inflight_requests_limit")
    end

    # ====================
    # lazy_connect
    # ====================

    def test_lazy_connect_true_is_serialized
      json_options = captured_json_options(lazy_connect: true)
      assert_equal true, json_options["lazy_connect"]
    end

    def test_lazy_connect_false_is_omitted
      # Matches the implementation: `lazy_connect` is only written to
      # json_options when truthy, mirroring how other boolean-ish options in
      # this file are handled (e.g. `cluster_mode_enabled`).
      json_options = captured_json_options(lazy_connect: false)
      refute json_options.key?("lazy_connect")
    end

    def test_lazy_connect_omitted_when_not_provided
      json_options = captured_json_options
      refute json_options.key?("lazy_connect")
    end

    # ====================
    # periodic_checks
    # ====================

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
      error = assert_raises(ArgumentError) do
        ::Valkey.new(host: "localhost", port: 6379, periodic_checks: "manual_interval")
      end
      assert_match(/periodic_checks must be a Hash/, error.message)
    end

    def test_periodic_checks_rejects_missing_manual_interval_and_disabled
      error = assert_raises(ArgumentError) do
        ::Valkey.new(host: "localhost", port: 6379, periodic_checks: {})
      end
      assert_match(/periodic_checks must contain :manual_interval or :disabled/, error.message)
    end

    def test_periodic_checks_rejects_non_integer_duration
      error = assert_raises(ArgumentError) do
        ::Valkey.new(
          host: "localhost",
          port: 6379,
          periodic_checks: { manual_interval: { duration_in_sec: "30" } }
        )
      end
      assert_match(/duration_in_sec must be an integer/, error.message)
    end

    def test_periodic_checks_rejects_negative_duration
      error = assert_raises(ArgumentError) do
        ::Valkey.new(
          host: "localhost",
          port: 6379,
          periodic_checks: { manual_interval: { duration_in_sec: -1 } }
        )
      end
      assert_match(/duration_in_sec must be non-negative/, error.message)
    end

    def test_periodic_checks_rejects_invalid_disabled_type
      error = assert_raises(ArgumentError) do
        ::Valkey.new(host: "localhost", port: 6379, periodic_checks: { disabled: "yes" })
      end
      assert_match(/periodic_checks disabled must be a boolean/, error.message)
    end

    # ====================
    # Combined options (multiple options serialized together correctly)
    # ====================

    def test_multiple_options_serialize_independently
      json_options = captured_json_options(
        read_from: :prefer_replica,
        client_az: "us-west-2a",
        inflight_requests_limit: 500,
        lazy_connect: true,
        periodic_checks: { disabled: true }
      )

      assert_equal "PreferReplica", json_options["read_from"]
      assert_equal "us-west-2a", json_options["client_az"]
      assert_equal 500, json_options["inflight_requests_limit"]
      assert_equal true, json_options["lazy_connect"]
      assert_equal({ "disabled" => true }, json_options["periodic_checks"])
    end
  end
end
