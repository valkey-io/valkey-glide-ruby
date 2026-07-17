# frozen_string_literal: true

# Unit tests for Valkey::OpenTelemetry's parent-span-context provider: registration,
# validation of the Hash a provider returns, and the resilience behavior (a provider
# that raises, or returns something malformed, must never propagate into the caller).
#
# These are pure unit tests: no connection, no real native OTel init, no server needed.
# setup/teardown only touch the provider itself (never @initialized/@config), since
# TestStandaloneOpenTelemetry (opentelemetry_test.rb) initializes native OTel exactly
# once per process and other tests rely on that state staying put.
module ValkeyTests
  module OpenTelemetryProvider
    VALID_CONTEXT = {
      trace_id: "0af7651916cd43dd8448eb211c80319c",
      span_id: "b7ad6b7169203331",
      trace_flags: 1,
      tracestate: "congo=t61rcWkgMzE"
    }.freeze

    def setup
      super if defined?(super)
      ::Valkey::OpenTelemetry.set_parent_span_context_provider(nil)
    end

    def teardown
      ::Valkey::OpenTelemetry.set_parent_span_context_provider(nil)
      super if defined?(super)
    end

    def test_no_provider_registered_returns_nil
      assert_nil ::Valkey::OpenTelemetry.parent_span_context
    end

    def test_valid_context_is_returned_unchanged
      ::Valkey::OpenTelemetry.set_parent_span_context_provider { VALID_CONTEXT }

      assert_equal VALID_CONTEXT, ::Valkey::OpenTelemetry.parent_span_context
    end

    def test_provider_returning_nil_context_returns_nil
      ::Valkey::OpenTelemetry.set_parent_span_context_provider { nil }

      assert_nil ::Valkey::OpenTelemetry.parent_span_context
    end

    def test_nil_tracestate_is_accepted
      ctx = VALID_CONTEXT.merge(tracestate: nil)
      ::Valkey::OpenTelemetry.set_parent_span_context_provider { ctx }

      assert_equal ctx, ::Valkey::OpenTelemetry.parent_span_context
    end

    def test_invalid_trace_id_is_rejected
      ctx = VALID_CONTEXT.merge(trace_id: "not-hex")
      ::Valkey::OpenTelemetry.set_parent_span_context_provider { ctx }

      _, err = capture_io { assert_nil ::Valkey::OpenTelemetry.parent_span_context }

      assert_match(/trace_id/, err)
    end

    def test_invalid_span_id_is_rejected
      ctx = VALID_CONTEXT.merge(span_id: "tooshort")
      ::Valkey::OpenTelemetry.set_parent_span_context_provider { ctx }

      _, err = capture_io { assert_nil ::Valkey::OpenTelemetry.parent_span_context }

      assert_match(/span_id/, err)
    end

    def test_out_of_range_trace_flags_is_rejected
      ctx = VALID_CONTEXT.merge(trace_flags: 256)
      ::Valkey::OpenTelemetry.set_parent_span_context_provider { ctx }

      _, err = capture_io { assert_nil ::Valkey::OpenTelemetry.parent_span_context }

      assert_match(/trace_flags/, err)
    end

    def test_non_string_tracestate_is_rejected
      ctx = VALID_CONTEXT.merge(tracestate: 12_345)
      ::Valkey::OpenTelemetry.set_parent_span_context_provider { ctx }

      _, err = capture_io { assert_nil ::Valkey::OpenTelemetry.parent_span_context }

      assert_match(/tracestate/, err)
    end

    def test_provider_raising_is_caught
      ::Valkey::OpenTelemetry.set_parent_span_context_provider { raise "boom" }

      _, err = capture_io { assert_nil ::Valkey::OpenTelemetry.parent_span_context }

      assert_match(/boom/, err)
    end

    def test_clearing_provider_with_nil
      ::Valkey::OpenTelemetry.set_parent_span_context_provider { VALID_CONTEXT }
      ::Valkey::OpenTelemetry.set_parent_span_context_provider(nil)

      assert_nil ::Valkey::OpenTelemetry.parent_span_context
    end

    def test_set_parent_span_context_provider_accepts_a_proc
      provider = proc { VALID_CONTEXT }
      ::Valkey::OpenTelemetry.set_parent_span_context_provider(provider)

      assert_equal VALID_CONTEXT, ::Valkey::OpenTelemetry.parent_span_context
    end

    # Exercises init(parent_span_context_provider:) without touching real native OTel
    # state: Bindings.init_open_telemetry is stubbed, and @initialized/@config are
    # saved and restored so this test is safe regardless of run order relative to
    # TestStandaloneOpenTelemetry's once-per-process native initialization.
    def test_init_accepts_parent_span_context_provider_kwarg
      original_initialized = ::Valkey::OpenTelemetry.instance_variable_get(:@initialized)
      original_config = ::Valkey::OpenTelemetry.config
      ::Valkey::OpenTelemetry.instance_variable_set(:@initialized, false)

      Valkey::Bindings.stub(:init_open_telemetry, FFI::Pointer::NULL) do
        ::Valkey::OpenTelemetry.init(
          traces: { endpoint: "file:///tmp/valkey_ruby_provider_kwarg_test.json" },
          parent_span_context_provider: -> { VALID_CONTEXT }
        )
      end

      assert_equal VALID_CONTEXT, ::Valkey::OpenTelemetry.parent_span_context
    ensure
      ::Valkey::OpenTelemetry.instance_variable_set(:@initialized, original_initialized)
      ::Valkey::OpenTelemetry.instance_variable_set(:@config, original_config)
    end
  end
end
