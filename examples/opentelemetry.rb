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

# Allow exporter flush
sleep 2

puts "OpenTelemetry initialized: #{Valkey::OpenTelemetry.initialized?}"
puts "Traces file: #{TRACES_FILE} (#{File.size?(TRACES_FILE) || 0} bytes)"
puts "Metrics file: #{METRICS_FILE} (#{File.size?(METRICS_FILE) || 0} bytes)"
puts "Done."
