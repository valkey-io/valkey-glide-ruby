# frozen_string_literal: true

# OpenTelemetry example using file exporters (no collector required).
#
# Run: bundle exec ruby examples/opentelemetry.rb
# Traces: /tmp/valkey_ruby_example_traces.json
# Metrics: /tmp/valkey_ruby_example_metrics.json

require "valkey"
require "fileutils"

TRACES_FILE = "/tmp/valkey_ruby_example_traces.json"
METRICS_FILE = "/tmp/valkey_ruby_example_metrics.json"

FileUtils.rm_f(TRACES_FILE)
FileUtils.rm_f(METRICS_FILE)

Valkey::OpenTelemetry.init(
  traces: {
    endpoint: "file://#{TRACES_FILE}",
    sample_percentage: 100
  },
  metrics: {
    endpoint: "file://#{METRICS_FILE}"
  },
  flush_interval_ms: 1000
)

host = ENV.fetch("VALKEY_HOST", "127.0.0.1")
port = Integer(ENV.fetch("VALKEY_PORT", 6379))

client = Valkey.new(host: host, port: port)

client.set("otel_key", "otel_value")
client.get("otel_key")
client.pipelined do |pipe|
  pipe.set("otel_pipe_1", "a")
  pipe.get("otel_pipe_1")
end

client.del("otel_key", "otel_pipe_1")
client.close

# Distributed tracing: register a parent_span_context_provider so command spans
# become children of the app's current trace instead of independent root spans.
# Here we hand-roll a fake W3C trace context (no dependency on the real
# opentelemetry-ruby gem); in a real app this would read from
# ::OpenTelemetry::Trace.current_span.context (see README).
fake_trace_id = "4bf92f3577b34da6a3ce929d0e0e4736"
fake_span_id = "00f067aa0ba902b7"

Valkey::OpenTelemetry.set_parent_span_context_provider do
  { trace_id: fake_trace_id, span_id: fake_span_id, trace_flags: 1, tracestate: nil }
end

client = Valkey.new(host: host, port: port)
client.set("otel_traced_key", "value") # span will be a child of fake_trace_id/fake_span_id
client.close

Valkey::OpenTelemetry.set_parent_span_context_provider(nil)

# Allow exporter flush
sleep 2

puts "OpenTelemetry initialized: #{Valkey::OpenTelemetry.initialized?}"
puts "Traces file: #{TRACES_FILE} (#{File.size?(TRACES_FILE) || 0} bytes)"
puts "Metrics file: #{METRICS_FILE} (#{File.size?(METRICS_FILE) || 0} bytes)"
puts "Done. Inspect #{TRACES_FILE} - the SET span for otel_traced_key should have " \
     "trace_id=#{fake_trace_id} and parent_span_id=#{fake_span_id}."
