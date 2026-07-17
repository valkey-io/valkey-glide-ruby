# frozen_string_literal: true

class Valkey
  # OpenTelemetry integration for Valkey GLIDE Ruby client.
  #
  # This module provides integration with the OpenTelemetry implementation
  # built into the Valkey GLIDE core (Rust FFI layer). Unlike typical Ruby
  # OpenTelemetry instrumentation, this directly configures the native
  # OpenTelemetry exporter in the Rust layer.
  #
  # @example Initialize with HTTP collector
  #   Valkey::OpenTelemetry.init(
  #     traces: {
  #       endpoint: "http://localhost:4318/v1/traces",
  #       sample_percentage: 10
  #     },
  #     metrics: {
  #       endpoint: "http://localhost:4318/v1/metrics"
  #     },
  #     flush_interval_ms: 5000
  #   )
  #
  # @example Initialize with gRPC collector
  #   Valkey::OpenTelemetry.init(
  #     traces: {
  #       endpoint: "grpc://localhost:4317",
  #       sample_percentage: 1
  #     },
  #     metrics: {
  #       endpoint: "grpc://localhost:4317"
  #     }
  #   )
  #
  # @example Initialize with file exporter (for testing)
  #   Valkey::OpenTelemetry.init(
  #     traces: {
  #       endpoint: "file:///tmp/valkey_traces.json",
  #       sample_percentage: 100
  #     },
  #     metrics: {
  #       endpoint: "file:///tmp/valkey_metrics.json"
  #     }
  #   )
  module OpenTelemetry
    @initialized = false
    @config = nil
    @parent_span_context_provider = nil

    class << self
      # Initialize OpenTelemetry in the Valkey GLIDE core.
      #
      # This method can only be called once per process. Subsequent calls will
      # be ignored with a warning.
      #
      # @param traces [Hash, nil] Traces configuration
      # @option traces [String] :endpoint The endpoint URL (required)
      #   Supported formats:
      #   - HTTP: http://localhost:4318/v1/traces
      #   - gRPC: grpc://localhost:4317
      #   - File: file:///absolute/path/to/traces.json
      # @option traces [Integer] :sample_percentage Sample percentage 0-100 (default: 1)
      #   Keep low (1-5%) in production for performance
      #
      # @param metrics [Hash, nil] Metrics configuration
      # @option metrics [String] :endpoint The endpoint URL (required)
      #   Same format as traces endpoint
      #
      # @param flush_interval_ms [Integer, nil] Flush interval in milliseconds (default: 5000)
      #   Must be a positive integer
      #
      # @param parent_span_context_provider [Proc, nil] Optional callable returning a Hash describing
      #   the current application span context (see {set_parent_span_context_provider}). Equivalent to
      #   calling {set_parent_span_context_provider} separately; provided here for convenience.
      #
      # @raise [ArgumentError] if neither traces nor metrics is provided
      # @raise [ArgumentError] if sample_percentage is not between 0-100
      # @raise [RuntimeError] if initialization fails
      #
      # @return [void]
      def init(traces: nil, metrics: nil, flush_interval_ms: nil, parent_span_context_provider: nil)
        if @initialized
          warn "Valkey::OpenTelemetry already initialized - ignoring new configuration"
          return
        end

        # Validate input
        raise ArgumentError, "At least one of traces or metrics must be provided" if traces.nil? && metrics.nil?

        if traces && traces[:sample_percentage]
          sample = traces[:sample_percentage]
          unless sample.is_a?(Integer) && sample >= 0 && sample <= 100
            raise ArgumentError, "sample_percentage must be an integer between 0 and 100, got: #{sample}"
          end
        end

        if flush_interval_ms && (!flush_interval_ms.is_a?(Integer) || flush_interval_ms <= 0)
          raise ArgumentError, "flush_interval_ms must be a positive integer, got: #{flush_interval_ms}"
        end

        # Build the configuration
        config = build_config(traces, metrics, flush_interval_ms)

        # Call the FFI function
        error_ptr = Bindings.init_open_telemetry(config)

        unless error_ptr.null?
          error_msg = error_ptr.read_string
          Bindings.free_c_string(error_ptr)
          raise "Failed to initialize OpenTelemetry: #{error_msg}"
        end

        @initialized = true
        @config = { traces: traces, metrics: metrics, flush_interval_ms: flush_interval_ms }
        set_parent_span_context_provider(parent_span_context_provider) if parent_span_context_provider

        puts "✅ Valkey OpenTelemetry initialized successfully"
        puts "   Traces: #{traces ? traces[:endpoint] : 'disabled'}"
        puts "   Metrics: #{metrics ? metrics[:endpoint] : 'disabled'}"
      end

      # Check if OpenTelemetry has been initialized.
      #
      # @return [Boolean] true if initialized
      def initialized?
        @initialized
      end

      # Determine if the current request should be sampled based on the configured sample percentage.
      #
      # @return [Boolean] true if the request should be sampled
      def should_sample?
        return false unless @initialized
        return false unless @config&.dig(:traces)

        sample_percentage = @config.dig(:traces, :sample_percentage) || 1
        rand(100) < sample_percentage
      end

      # Get the current OpenTelemetry configuration.
      #
      # @return [Hash, nil] the configuration hash or nil if not initialized
      attr_reader :config

      # Register a callable that returns the current application span context, so that
      # spans created for Valkey commands become children of it instead of independent
      # root spans. This is how distributed tracing context (e.g. from the Rails request
      # span) is propagated into the native OpenTelemetry spans created for each command.
      #
      # @param callable [Proc, nil] Called with no arguments before each command. Must return
      #   either nil (no active context - the command gets an independent span) or a Hash with:
      #   - :trace_id [String] 32-character lowercase hex trace ID
      #   - :span_id [String] 16-character lowercase hex span ID
      #   - :trace_flags [Integer] 0-255
      #   - :tracestate [String, nil] W3C tracestate header, optional
      #   Pass nil (and no block) to clear a previously registered provider.
      #
      # @example
      #   Valkey::OpenTelemetry.set_parent_span_context_provider do
      #     span = ::OpenTelemetry::Trace.current_span
      #     next nil unless span.context.valid?
      #
      #     {
      #       trace_id: span.context.hex_trace_id,
      #       span_id: span.context.hex_span_id,
      #       trace_flags: span.context.trace_flags.sampled? ? 1 : 0,
      #       tracestate: span.context.tracestate.to_s
      #     }
      #   end
      #
      # @return [void]
      def set_parent_span_context_provider(callable = nil, &block)
        @parent_span_context_provider = block || callable
      end

      # Invoke the registered parent-span-context provider (if any) and return a validated
      # context Hash, or nil if no provider is registered, the provider returned nil, the
      # provider raised, or the returned context failed validation.
      #
      # @return [Hash, nil]
      def parent_span_context
        return nil unless @parent_span_context_provider

        ctx = @parent_span_context_provider.call
        return nil if ctx.nil?

        validate_parent_span_context!(ctx)
        ctx
      rescue StandardError => e
        warn "Valkey::OpenTelemetry parent_span_context_provider failed: #{e.message}"
        nil
      end

      # Reset initialization state (for testing only).
      #
      # @api private
      def reset!
        @initialized = false
        @config = nil
        @parent_span_context_provider = nil
      end

      private

      def validate_parent_span_context!(ctx)
        raise ArgumentError, "parent span context must be a Hash, got: #{ctx.class}" unless ctx.is_a?(Hash)

        unless ctx[:trace_id].is_a?(String) && ctx[:trace_id].match?(/\A[0-9a-f]{32}\z/)
          raise ArgumentError, "trace_id must be a 32-character lowercase hex string, got: #{ctx[:trace_id].inspect}"
        end

        unless ctx[:span_id].is_a?(String) && ctx[:span_id].match?(/\A[0-9a-f]{16}\z/)
          raise ArgumentError, "span_id must be a 16-character lowercase hex string, got: #{ctx[:span_id].inspect}"
        end

        trace_flags = ctx[:trace_flags]
        unless trace_flags.is_a?(Integer) && trace_flags >= 0 && trace_flags <= 255
          raise ArgumentError, "trace_flags must be an integer between 0 and 255, got: #{trace_flags.inspect}"
        end

        tracestate = ctx[:tracestate]
        return if tracestate.nil? || tracestate.is_a?(String)

        raise ArgumentError, "tracestate must be a String or nil, got: #{tracestate.class}"
      end

      def build_config(traces, metrics, flush_interval_ms)
        config_struct = Bindings::OpenTelemetryConfig.new

        # Configure traces if provided
        if traces
          validate_endpoint!(traces[:endpoint], "traces")

          traces_struct = Bindings::OpenTelemetryTracesConfig.new
          traces_struct[:endpoint] = FFI::MemoryPointer.from_string(traces[:endpoint])

          if traces[:sample_percentage]
            traces_struct[:has_sample_percentage] = true
            traces_struct[:sample_percentage] = traces[:sample_percentage]
          else
            traces_struct[:has_sample_percentage] = false
            traces_struct[:sample_percentage] = 1 # Default
          end

          config_struct[:traces] = traces_struct.pointer
        else
          config_struct[:traces] = FFI::Pointer::NULL
        end

        # Configure metrics if provided
        if metrics
          validate_endpoint!(metrics[:endpoint], "metrics")

          metrics_struct = Bindings::OpenTelemetryMetricsConfig.new
          metrics_struct[:endpoint] = FFI::MemoryPointer.from_string(metrics[:endpoint])
          config_struct[:metrics] = metrics_struct.pointer
        else
          config_struct[:metrics] = FFI::Pointer::NULL
        end

        # Configure flush interval
        if flush_interval_ms
          config_struct[:has_flush_interval_ms] = true
          config_struct[:flush_interval_ms] = flush_interval_ms
        else
          config_struct[:has_flush_interval_ms] = false
          config_struct[:flush_interval_ms] = 5000 # Default
        end

        config_struct
      end

      def validate_endpoint!(endpoint, type)
        unless endpoint.is_a?(String) && !endpoint.empty?
          raise ArgumentError, "#{type} endpoint must be a non-empty string"
        end

        # Validate endpoint format
        valid_prefixes = %w[http:// https:// grpc:// file://]
        return if valid_prefixes.any? { |prefix| endpoint.start_with?(prefix) }

        raise ArgumentError, "#{type} endpoint must start with one of: #{valid_prefixes.join(', ')}"
      end
    end
  end
end
