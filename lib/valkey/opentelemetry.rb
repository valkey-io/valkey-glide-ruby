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
      # @raise [ArgumentError] if neither traces nor metrics is provided
      # @raise [ArgumentError] if sample_percentage is not between 0-100
      # @raise [RuntimeError] if initialization fails
      #
      # @return [void]
      def init(traces: nil, metrics: nil, flush_interval_ms: nil)
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

      # Reset initialization state (for testing only).
      #
      # @api private
      def reset!
        @initialized = false
        @config = nil
      end

      private

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
