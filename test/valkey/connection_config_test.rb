# frozen_string_literal: true

# Unit tests for the connection config options added in this PR: read_from,
# client_az, inflight_requests_limit, lazy_connect, periodic_checks.
#
# These are mode-agnostic (standalone client construction is enough to exercise
# the Ruby-side validation/serialization); the module is included by both the
# standalone and cluster test classes via Dir["valkey/**/*.rb"] autoloading.
module ValkeyTests
  module ConnectionConfig
    # NOTE: "LowestLatency" is a valid read_from value per the FFI docs
    # (ffi/src/lib.rs) and is accepted by Ruby's validation, but the currently
    # vendored glide-core build panics with `todo!()` when converting it
    # (glide-core/src/client/types.rs, `impl From<protobuf::ConnectionRequest>`,
    # reached via ffi/src/lib.rs's create_client_from_uri -> ConnectionRequest::from).
    # This is an upstream native-core gap, not a Ruby-side bug, so it is exercised
    # in its own test below (skipped) rather than in the shared happy-path loops,
    # which would otherwise abort the whole test process.
    READ_FROM_VALUES_SAFE_TO_CONNECT = {
      "Primary" => :primary,
      "PreferReplica" => :prefer_replica,
      "AZAffinity" => :az_affinity,
      "AZAffinityReplicasAndPrimary" => :az_affinity_replicas_and_primary
    }.freeze

    # ====================
    # read_from
    # ====================

    def test_read_from_accepts_canonical_strings
      READ_FROM_VALUES_SAFE_TO_CONNECT.each_key do |value|
        client = ::Valkey.new(host: "localhost", port: 6379, read_from: value, lazy_connect: true)
        assert_equal "PONG", client.ping
        client.close
      end
    end

    def test_read_from_accepts_ruby_friendly_symbols
      READ_FROM_VALUES_SAFE_TO_CONNECT.each_value do |symbol|
        client = ::Valkey.new(host: "localhost", port: 6379, read_from: symbol, lazy_connect: true)
        assert_equal "PONG", client.ping
        client.close
      end
    end

    def test_read_from_lowest_latency_is_accepted_by_ruby_validation
      # Ruby-side validation/serialization for "LowestLatency" is correct (it's
      # one of the 5 canonical values documented in ffi/src/lib.rs), but the
      # vendored glide-core build cannot actually service it -- see the module
      # comment above. Skipped rather than asserted against a live connection
      # to avoid crashing the whole test process on an upstream `todo!()` panic.
      skip("LowestLatency read_from hits an unimplemented!() panic in the vendored glide-core build")

      client = ::Valkey.new(host: "localhost", port: 6379, read_from: "LowestLatency", lazy_connect: true)
      assert_equal "PONG", client.ping
      client.close
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

    # ====================
    # client_az
    # ====================

    def test_client_az_accepts_string
      client = ::Valkey.new(host: "localhost", port: 6379, client_az: "us-west-2a", lazy_connect: true)
      assert_equal "PONG", client.ping
      client.close
    end

    def test_client_az_rejects_non_string
      error = assert_raises(ArgumentError) do
        ::Valkey.new(host: "localhost", port: 6379, client_az: 123)
      end
      assert_match(/client_az must be a string/, error.message)
    end

    # ====================
    # inflight_requests_limit
    # ====================

    def test_inflight_requests_limit_accepts_positive_integer
      client = ::Valkey.new(host: "localhost", port: 6379, inflight_requests_limit: 1000, lazy_connect: true)
      assert_equal "PONG", client.ping
      client.close
    end

    def test_inflight_requests_limit_accepts_zero
      client = ::Valkey.new(host: "localhost", port: 6379, inflight_requests_limit: 0, lazy_connect: true)
      assert_equal "PONG", client.ping
      client.close
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

    # ====================
    # lazy_connect
    # ====================

    def test_lazy_connect_true_still_allows_commands
      client = ::Valkey.new(host: "localhost", port: 6379, lazy_connect: true)
      assert_equal "PONG", client.ping
      client.close
    end

    def test_lazy_connect_false_behaves_like_default
      client = ::Valkey.new(host: "localhost", port: 6379, lazy_connect: false)
      assert_equal "PONG", client.ping
      client.close
    end

    # ====================
    # periodic_checks
    # ====================

    def test_periodic_checks_accepts_manual_interval
      client = ::Valkey.new(
        host: "localhost",
        port: 6379,
        periodic_checks: { manual_interval: { duration_in_sec: 30 } },
        lazy_connect: true
      )
      assert_equal "PONG", client.ping
      client.close
    end

    def test_periodic_checks_accepts_manual_interval_with_string_keys
      client = ::Valkey.new(
        host: "localhost",
        port: 6379,
        periodic_checks: { "manual_interval" => { "duration_in_sec" => 30 } },
        lazy_connect: true
      )
      assert_equal "PONG", client.ping
      client.close
    end

    def test_periodic_checks_accepts_disabled
      client = ::Valkey.new(
        host: "localhost",
        port: 6379,
        periodic_checks: { disabled: true },
        lazy_connect: true
      )
      assert_equal "PONG", client.ping
      client.close
    end

    def test_periodic_checks_is_a_noop_on_standalone
      # periodic_checks is cluster-only in effect; standalone must accept it
      # without raising, per the parent plan's key decision.
      skip("only relevant for standalone mode") if cluster_mode?

      client = ::Valkey.new(
        host: "localhost",
        port: 6379,
        periodic_checks: { manual_interval: { duration_in_sec: 5 } },
        lazy_connect: true
      )
      assert_equal "PONG", client.ping
      client.close
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
  end
end
