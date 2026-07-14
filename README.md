# Valkey GLIDE for Ruby

Valkey General Language Independent Driver for the Enterprise (GLIDE) is the official open-source Valkey client library, proudly part of the [Valkey](https://valkey.io) organization. The Ruby gem (`valkey-rb`) wraps [Valkey GLIDE Core](https://github.com/valkey-io/valkey-glide) (Rust) and aims to be a **drop-in replacement for [redis-rb](https://github.com/redis/redis-rb)** while delivering GLIDE performance, reliability, and enterprise features.

## Why Choose Valkey GLIDE?

- **Community and Open Source**: Join our vibrant community and contribute to the project.
- **Reliability**: Built with best practices learned from over a decade of operating Redis OSS-compatible services.
- **Performance**: Optimized for high performance and low latency via the Rust-based GLIDE core.
- **High Availability**: Cluster-aware routing, reconnection, and fault tolerance.
- **Cross-Language Consistency**: Same core driver as Python, Java, Node.js, and Go clients.
- **Drop-in Replacement**: Familiar redis-rb-style API (`Valkey.new`, command methods, `pipelined`, URL parsing).
- **Observability**: Native OpenTelemetry tracing and client statistics.

## Documentation

- **Command coverage**: [Implementation status wiki](https://github.com/valkey-io/valkey-glide-ruby/wiki/The-implementation-status-of-the-Valkey-commands)
- **Valkey GLIDE overview**: [glide.valkey.io](https://glide.valkey.io/)
- **Supported engine versions**: [valkey-glide README — Supported Engine Versions](https://github.com/valkey-io/valkey-glide/blob/main/README.md#supported-engine-versions)
- **Local development**: [DEVELOPER.md](./DEVELOPER.md)

## Supported Engine Versions

| Engine Type | 6.2 | 7.0 | 7.1 | 7.2 | 8.0 | 8.1 | 9.0 |
|-------------|-----|-----|-----|-----|-----|-----|-----|
| Valkey      | -   | -   | -   | ✓   | ✓   | ✓   | ✓   |
| Redis OSS   | ✓   | ✓   | ✓   | ✓   | -   | -   | -   |

## Getting Started — Ruby Wrapper

### System Requirements

The release of Valkey GLIDE Ruby was tested on the following platforms:

**Linux:**

- Ubuntu 20+ (x86_64/amd64 and arm64/aarch64)
- Amazon Linux 2 (AL2) and 2023 (AL2023) (x86_64)
- Alpine Linux 3.18+ (x86_64 and arm64/aarch64) — musl libc

**macOS:**

- macOS 14.7+ (Apple silicon / aarch64)
- macOS 13.7+ (x86_64 / amd64)

### Ruby Supported Versions

| Ruby Version | MRI | JRuby |
|--------------|-----|-------|
| 2.6          | ✓   | -     |
| 2.7          | ✓   | -     |
| 3.0 – 3.4    | ✓   | ✓     |

Minimum Ruby version: **2.6.0** (see `valkey.gemspec`).

### Installation and Setup

Install from RubyGems:

```bash
gem install valkey-rb
```

Or add to your `Gemfile`:

```ruby
gem "valkey-rb"
```

Verify installation:

```bash
ruby -e 'require "valkey"; puts Valkey::VERSION'
```

The gem ships prebuilt native libraries (`libglide_ffi.so` on Linux, `libglide_ffi.dylib` on macOS) and depends on the [`ffi`](https://github.com/ffi/ffi) gem.

## Basic Examples

### Standalone Mode

```ruby
require "valkey"

client = Valkey.new(host: "localhost", port: 6379)

client.set("mykey", "hello world")
# => "OK"

client.get("mykey")
# => "hello world"

client.close
```

### Standalone with URL (redis-rb compatible)

```ruby
client = Valkey.new(url: "redis://localhost:6379/0")
# TLS: rediss://user:password@localhost:6380/0

client.ping
# => "PONG"
```

### Cluster Mode

```ruby
nodes = [
  { host: "127.0.0.1", port: 7000 },
  { host: "127.0.0.1", port: 7001 },
  { host: "127.0.0.1", port: 7002 },
  { host: "127.0.0.1", port: 7003 },
  { host: "127.0.0.1", port: 7004 },
  { host: "127.0.0.1", port: 7005 }
]

client = Valkey.new(nodes: nodes, cluster_mode: true)
client.set("foo", "bar")
client.get("foo")
# => "bar"
```

### Pipelining

Batch multiple commands in a single network round trip (non-atomic pipeline):

```ruby
results = client.pipelined do |pipe|
  pipe.set("key1", "value1")
  pipe.get("key1")
  pipe.incr("counter")
end
# => ["OK", "value1", 1]
```

> **Note:** Transactional commands (`MULTI` / `EXEC` / `DISCARD`) in a pipeline are executed sequentially as a workaround for FFI batch stability. Prefer `multi` / `exec` on the main client for transactions.

### Generic Command Dispatch (`call` / `call_v`)

Not every command has a dedicated method yet. `call`/`call_v` are the escape hatch — send any
command as plain arguments and get the raw reply back, matching `redis-client`'s `#call`/`#call_v`:

```ruby
client.call("SET", "mykey", "value")
# => "OK"

client.call_v(["MGET"] + keys)
```

`call`/`call_v` apply the same argument coercion as `redis-client`:

```ruby
# Integers/Floats auto-stringify
client.call("SET", "mykey", 42)
# equivalent to call("SET", "mykey", "42")

# Arrays flatten (including nested arrays)
client.call("LPUSH", "list", [1, 2, 3])
# equivalent to call("LPUSH", "list", "1", "2", "3")

# Hashes flatten to alternating key/value
client.call("HMSET", "hash", { "foo" => "1" })
# equivalent to call("HMSET", "hash", "foo", "1")

# Keyword args become trailing command flags (call only, not call_v):
# a truthy value emits the upcased flag name; a non-boolean value also emits
# the stringified value. Falsy/nil values are dropped entirely, not stringified.
client.call("SET", "k", "v", nx: true, ex: 60)
# equivalent to call("SET", "k", "v", "NX", "EX", "60")
client.call("SET", "k", "v", nx: false, ex: nil)
# equivalent to call("SET", "k", "v")
```

`call_v` takes the whole command as a single Array (no keyword flags) — useful when the command is
built dynamically. Both return the raw reply with no type-casting based on the command name.

### Connection Options (redis-rb compatible)

| Option | Description |
|--------|-------------|
| `host`, `port` | Server address (default `127.0.0.1:6379`) |
| `url` | `redis://` or `rediss://` URI (merged with explicit options) |
| `db` | Database index (standalone only) |
| `password`, `username` | Authentication |
| `timeout` | Request timeout in seconds (default `5.0`) |
| `connect_timeout` | Connection timeout in seconds |
| `ssl`, `ssl_params` | TLS (`ca_file`, `cert`, `key`, `ca_path`, `root_certs`) |
| `cluster_mode` | Enable cluster client |
| `nodes` | Array of `{ host:, port: }` hashes |
| `protocol` | `:resp2` (default) or `:resp3` |
| `client_name` | `CLIENT SETNAME` value |
| `reconnect_attempts`, `reconnect_delay`, `reconnect_delay_max` | Connection retry strategy |
| `read_from` *(GLIDE-native)* | Read routing: `:primary`, `:prefer_replica`, `:az_affinity`, `:az_affinity_replicas_and_primary` symbols, the exact-match GLIDE strings (e.g. `"PreferReplica"`), or the `Valkey::ReadFrom::*` constants (e.g. `Valkey::ReadFrom::PREFER_REPLICA`). `:az_affinity`/`:az_affinity_replicas_and_primary` require `client_az` to also be set. `LowestLatency` is a valid GLIDE value but not yet usable via the vendored native library. |
| `client_az` *(GLIDE-native)* | Availability-zone identifier for `:az_affinity` / `:az_affinity_replicas_and_primary` routing (e.g. `"us-west-2a"`) |
| `inflight_requests_limit` *(GLIDE-native)* | Maximum concurrent in-flight requests (non-negative integer) |
| `lazy_connect` *(GLIDE-native)* | Delay the actual connection until the first command is sent |
| `periodic_checks` *(GLIDE-native)* | Cluster topology health checks: `{ manual_interval: { duration_in_sec: N } }` or `{ disabled: true }`. Accepted (as a no-op) on standalone connections. |

```ruby
client = Valkey.new(
  host: "localhost",
  port: 6379,
  timeout: 2.0,
  connect_timeout: 1.0,
  client_name: "my-app",
  protocol: :resp3
)
```

## OpenTelemetry

Valkey GLIDE Ruby configures OpenTelemetry in the **native Rust core** (not via the Ruby `opentelemetry-sdk` gem). Initialize once per process before creating clients:

```ruby
require "valkey"

Valkey::OpenTelemetry.init(
  traces: {
    endpoint: "http://localhost:4318/v1/traces",
    sample_percentage: 10
  },
  metrics: {
    endpoint: "http://localhost:4318/v1/metrics"
  },
  flush_interval_ms: 5000
)

client = Valkey.new(host: "localhost", port: 6379)
client.set("key", "value")  # traced when sampling applies
```

**Supported endpoint formats:**

- HTTP/HTTPS: `http://localhost:4318/v1/traces`
- gRPC: `grpc://localhost:4317`
- File (testing): `file:///tmp/valkey_traces.json`

OpenTelemetry can only be initialized **once per process**. Spans are created in the FFI layer when sampling is enabled.

## Examples

Runnable examples are in [examples/](./examples/):

```bash
bundle exec ruby examples/standalone.rb
bundle exec ruby examples/pipelining.rb
bundle exec ruby examples/opentelemetry.rb
```

See [examples/README.md](./examples/README.md) for cluster setup and environment variables.

## Client Statistics

Monitor global client metrics (shared across all clients in the process):

```ruby
stats = client.get_statistics
# alias: client.statistics

puts "Connections: #{stats[:total_connections]}"
puts "Clients: #{stats[:total_clients]}"
puts "Compressed values: #{stats[:total_values_compressed]}"
```

Available keys: `:total_connections`, `:total_clients`, `:total_values_compressed`, `:total_values_decompressed`, `:total_original_bytes`, `:total_bytes_compressed`, `:total_bytes_decompressed`, `:compression_skipped_count`.

## Pub/Sub

Pub/Sub uses a native callback registered at connection time. Configure subscriptions via command modules (`subscribe`, `psubscribe`, etc.). See [DEVELOPER.md](./DEVELOPER.md) and integration tests in `test/valkey/pubsub_commands_test.rb` for details.

## Layout of Ruby Code

| Path | Purpose |
|------|---------|
| `lib/valkey.rb` | Main client: connection, pipelining, response conversion |
| `lib/valkey/bindings.rb` | FFI bindings to `libglide_ffi` |
| `lib/valkey/commands/` | Command modules (strings, hashes, streams, cluster, JSON, vector search, …) |
| `lib/valkey/opentelemetry.rb` | OpenTelemetry configuration |
| `lib/valkey/pipeline.rb` | Pipeline command batching |
| `test/valkey/` | Standalone integration tests |
| `test/cluster/` | Cluster integration tests |
| `test/lint/` | Shared lint tests (redis-rb compatibility patterns) |

## redis-rb Compatibility

This client mirrors redis-rb conventions where possible:

- `Valkey.new` with `url`, `host`, `port`, `db`, `ssl_params`
- Command method names and argument ordering aligned with redis-rb
- `pipelined`, `multi` / `exec`, `disconnect!` (alias of `close`)

Not every redis-rb API is implemented yet. See the [command implementation wiki](https://github.com/valkey-io/valkey-glide-ruby/wiki/The-implementation-status-of-the-Valkey-commands) for coverage.

## Building and Testing

Instructions for building from source, updating the FFI library, running tests, and contributing are in [DEVELOPER.md](./DEVELOPER.md).

For AI-assisted development, see [AGENTS.md](./AGENTS.md) and [CLAUDE.md](./CLAUDE.md).

Contributing: [CONTRIBUTING.md](./CONTRIBUTING.md).

## Community and Feedback

We encourage you to join our community to support, share feedback, and ask questions on Valkey Slack: [Join Valkey Slack](https://join.slack.com/t/valkey-oss-developer/shared_invite/zt-2nxs51chx-EB9hu9Qdch3GMfRcztTSkQ).

Report issues: [valkey-glide-ruby issues](https://github.com/valkey-io/valkey-glide-ruby/issues).

## License

Apache-2.0 — see [LICENSE](https://github.com/valkey-io/valkey-glide-ruby/blob/main/LICENSE) in the repository.
