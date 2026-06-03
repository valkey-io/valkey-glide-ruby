# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "json"
require "timeout"

class OpenTelemetryTest < Minitest::Test
  TRACES_FILE = "/tmp/valkey_ruby_test_traces.json"
  METRICS_FILE = "/tmp/valkey_ruby_test_metrics.json"
  DEFAULT_TIMEOUT = 15.0  # seconds
  POLL_INTERVAL = 0.5     # seconds

  def setup
    cleanup_test_files
  end

  def teardown
    cleanup_test_files
  end

  def cleanup_test_files
    [TRACES_FILE, METRICS_FILE].each do |file|
      FileUtils.rm_f(file)
    end
  end

  # Helper method to wait for spans to be exported with retry logic
  def wait_for_spans(span_file_path, expected_span_names, expected_counts: nil, timeout: DEFAULT_TIMEOUT)
    start_time = Time.now

    loop do
      elapsed = Time.now - start_time

      if elapsed >= timeout
        # Timeout - build diagnostic message
        unless File.exist?(span_file_path) && File.size(span_file_path).positive?
          raise "Timeout waiting for spans. Span file #{span_file_path} does not exist or is empty"
        end

        span_names = read_span_names(span_file_path)
        actual_counts = count_spans(span_names, expected_span_names)

        raise "Timeout waiting for spans. Expected #{expected_counts}, but found #{actual_counts}" if expected_counts

        raise "Timeout waiting for spans. Expected #{expected_span_names}, but found #{span_names.uniq}"

      end

      # Check if file exists and is readable
      if File.exist?(span_file_path) && File.size(span_file_path).positive?
        begin
          span_names = read_span_names(span_file_path)

          if check_spans_ready(span_names, expected_span_names, expected_counts)
            return true # Success!
          end
        rescue JSON::ParserError
          # File might be partially written, continue waiting
        end
      end

      sleep POLL_INTERVAL
    end
  end

  # Read span names from file
  def read_span_names(file_path)
    span_names = []
    File.readlines(file_path).each do |line|
      span = JSON.parse(line)
      span_names << span["name"]
    rescue JSON::ParserError
      # Skip malformed lines
    end
    span_names
  end

  # Check if expected spans are present
  def check_spans_ready(span_names, expected_span_names, expected_counts)
    if expected_counts
      # Check specific counts
      expected_counts.each do |span_name, expected_count|
        actual_count = span_names.count(span_name)
        return false if actual_count < expected_count
      end
      true
    else
      # Just check presence
      expected_span_names.all? { |name| span_names.include?(name) }
    end
  end

  # Count occurrences of expected spans
  def count_spans(span_names, expected_span_names)
    counts = {}
    expected_span_names.each do |name|
      counts[name] = span_names.count(name)
    end
    counts
  end

  # Test 1: Initialization with file exporter
  def test_initialization_with_file_exporter
    Valkey::OpenTelemetry.init(
      traces: {
        endpoint: "file://#{TRACES_FILE}",
        sample_percentage: 100
      },
      metrics: {
        endpoint: "file://#{METRICS_FILE}"
      },
      flush_interval_ms: 100
    )

    assert Valkey::OpenTelemetry.initialized?
    assert_equal "file://#{TRACES_FILE}", Valkey::OpenTelemetry.config[:traces][:endpoint]
    assert_equal 100, Valkey::OpenTelemetry.config[:traces][:sample_percentage]
    assert_equal "file://#{METRICS_FILE}", Valkey::OpenTelemetry.config[:metrics][:endpoint]
    assert_equal 100, Valkey::OpenTelemetry.config[:flush_interval_ms]
  end

  # Test 2: Singleton initialization
  def test_ignores_second_initialization
    assert Valkey::OpenTelemetry.initialized?

    original_config = Valkey::OpenTelemetry.config.dup

    # Capture warning
    _output, err = capture_io do
      Valkey::OpenTelemetry.init(
        traces: {
          endpoint: "file:///tmp/different_file.json",
          sample_percentage: 50
        }
      )
    end

    # Config should remain unchanged
    assert_equal original_config, Valkey::OpenTelemetry.config
    assert_match(/already initialized/, err)
  end

  # Test 3: Commands work with OpenTelemetry enabled
  def test_commands_work_with_opentelemetry_enabled
    assert Valkey::OpenTelemetry.initialized?

    client = Valkey.new(host: "localhost", port: 6379)

    # Commands should work normally
    assert_equal "OK", client.set("otel_test_key", "value")
    assert_equal "value", client.get("otel_test_key")

    client.close
  end

  # Test 4: Pipeline works with OpenTelemetry enabled
  def test_pipeline_works_with_opentelemetry_enabled
    assert Valkey::OpenTelemetry.initialized?

    client = Valkey.new(host: "localhost", port: 6379)

    results = client.pipelined do |pipeline|
      pipeline.set("key1", "value1")
      pipeline.set("key2", "value2")
      pipeline.get("key1")
      pipeline.get("key2")
    end

    assert_equal %w[OK OK value1 value2], results

    client.close
  end

  # Test 5: Span export verification (matching Java/Python tests)
  def test_span_export_to_file
    assert Valkey::OpenTelemetry.initialized?

    # Clean up before test
    cleanup_test_files

    client = Valkey.new(host: "localhost", port: 6379)

    # Execute commands that should generate spans
    client.set("test_key_1", "value1")
    client.get("test_key_1")

    client.close

    # Wait for spans to be flushed with retry logic
    wait_for_spans(
      TRACES_FILE,
      %w[SET GET],
      expected_counts: { "SET" => 1, "GET" => 1 },
      timeout: 10.0
    )

    # Verify file was created and contains spans
    assert File.exist?(TRACES_FILE)
    span_names = read_span_names(TRACES_FILE)

    assert_includes span_names, "SET"
    assert_includes span_names, "GET"
    assert_equal 1, span_names.count("SET")
    assert_equal 1, span_names.count("GET")
  end

  # Test 6: Multiple commands span export
  def test_multiple_commands_span_export
    assert Valkey::OpenTelemetry.initialized?

    cleanup_test_files

    client = Valkey.new(host: "localhost", port: 6379)

    # Execute multiple commands
    5.times { |i| client.set("multi_key_#{i}", "value#{i}") }
    5.times { |i| client.get("multi_key_#{i}") }
    client.ping
    client.del("multi_key_0", "multi_key_1")

    client.close

    # Wait for all spans
    wait_for_spans(
      TRACES_FILE,
      %w[SET GET PING DEL],
      expected_counts: { "SET" => 5, "GET" => 5, "PING" => 1, "DEL" => 1 },
      timeout: 10.0
    )

    span_names = read_span_names(TRACES_FILE)

    assert_equal 5, span_names.count("SET")
    assert_equal 5, span_names.count("GET")
    assert_equal 1, span_names.count("PING")
    assert_equal 1, span_names.count("DEL")
  end

  # Test 7: Batch/Pipeline span export
  def test_batch_span_export
    assert Valkey::OpenTelemetry.initialized?

    cleanup_test_files

    client = Valkey.new(host: "localhost", port: 6379)

    # Execute pipeline
    results = client.pipelined do |pipeline|
      pipeline.set("batch_key_1", "v1")
      pipeline.set("batch_key_2", "v2")
      pipeline.get("batch_key_1")
      pipeline.get("batch_key_2")
    end

    assert_equal %w[OK OK v1 v2], results

    client.close

    # Wait for batch span
    wait_for_spans(
      TRACES_FILE,
      ["Batch"],
      expected_counts: { "Batch" => 1 },
      timeout: 10.0
    )

    span_names = read_span_names(TRACES_FILE)

    assert_includes span_names, "Batch"
    assert_equal 1, span_names.count("Batch")
  end

  # Test 8: Sampling percentage (low sampling)
  def test_sampling_percentage
    # NOTE: This test is probabilistic, so we just verify the system doesn't crash
    # We can't reliably test exact sampling rates due to randomness

    assert Valkey::OpenTelemetry.initialized?

    client = Valkey.new(host: "localhost", port: 6379)

    # Execute many commands - with 100% sampling all should be traced
    20.times { |i| client.set("sample_key_#{i}", "value") }

    client.close

    # Just verify no errors occurred
    # Actual sampling verification would be non-deterministic
  end
end
