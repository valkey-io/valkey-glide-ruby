
# Valkey GLIDE for Ruby

Valkey General Language Independent Driver for the Enterprise (GLIDE) is the official open-source Valkey client library, part of the [Valkey](https://valkey.io) organization. The Ruby gem (`valkey-glide-rb`) wraps [Valkey GLIDE Core](https://github.com/valkey-io/valkey-glide), giving Ruby applications the performance and reliability of the GLIDE core.

## Features

- **Community and Open Source**: Developed in the open under the Valkey organization; contributions welcome.
- **Reliability**: Built with best practices learned from over a decade of operating Redis OSS-compatible services.
- **Performance**: Optimized for high performance and low latency via the Rust-based GLIDE core.
- **High Availability**: Cluster-aware routing, reconnection, and fault tolerance.
- **Cross-Language Consistency**: Same core driver as Python, Java, Node.js, and Go clients.
- **Observability**: Native OpenTelemetry tracing and client statistics.

## Documentation

- **Command coverage**: [Implementation status wiki](https://github.com/valkey-io/valkey-glide-ruby/wiki/The-implementation-status-of-the-Valkey-commands)
- **Valkey GLIDE overview**: [glide.valkey.io](https://glide.valkey.io/)
- **Supported engine versions**: [valkey-glide README: Supported Engine Versions](https://github.com/valkey-io/valkey-glide/blob/main/README.md#supported-engine-versions)

## Supported Engine Versions

| Engine Type | 6.2 | 7.0 | 7.1 | 7.2 | 8.0 | 8.1 | 9.0 |
|-------------|-----|-----|-----|-----|-----|-----|-----|
| Valkey      | -   | -   | -   | ✓   | ✓   | ✓   | ✓   |
| Redis OSS   | ✓   | ✓   | ✓   | ✓   | -   | -   | -   |

## Getting Started

### System Requirements

- glibc 2.17+ or musl 1.2.3+
- Ruby 3.0+

#### Supported OS

The following platforms are tested in CI:
- Ubuntu 24 (x86_64 and arm64)
- Alpine Linux 3 (x86_64 and arm64, via musl targets)
- macOS 14+ (Apple silicon / arm64)

**Notes:** valkey-glide-rb depends on the compiled Rust core. For unsupported OS like Intel Mac, you 
will need to build Valkey GLIDE manually.

### Installation and Setup

Install from RubyGems:

```bash
gem install valkey-glide-rb
```

Or add to your `Gemfile`:

```ruby
gem "valkey-glide-rb"
```

Verify installation:

```bash
ruby -e 'require "valkey"; puts Valkey::VERSION'
```

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

### Connection Options

| Option | Description |
|--------|-------------|
| `host`, `port` | Server address (default `127.0.0.1:6379`) |
| `url` | `redis://`, `rediss://`, `valkey://`, or `valkeys://` URI (merged with explicit options) |
| `db` | Database index (standalone only) |
| `password`, `username` | Authentication |
| `timeout` | Request timeout in seconds (default `5.0`) |
| `connect_timeout` | Connection timeout in seconds |
| `ssl`| Enable TLS if true |
| `ssl_params` | TLS options {`ca_file`, `cert`, `key`, `ca_path`, `root_certs`} |
| `cluster_mode` | Enable cluster client |
| `nodes` | Array of `{ host:, port: }` hashes |
| `protocol` | `:resp2` (default) or `:resp3` |
| `client_name` | `CLIENT SETNAME` value |
| `lib_name` | Full override of the `CLIENT SETINFO LIB-NAME` value (default `GlideRuby`). Accepts a `String`, a `Symbol`, or `nil`. Validated by glide-core: printable ASCII excluding space, `(` and `)`, plus at most one matched trailing `(tag)`; an invalid value raises `Valkey::CannotConnectError` at client creation. An empty value falls back to the default. |
| `client_info_tag` | Appends a parenthesized tag to the resolved library name while keeping the base token intact — e.g. `GlideRuby(my-framework:1.0)`, or `<lib_name>(<tag>)` when combined with `lib_name`. An empty tag is treated as absent (no suffix). Like `lib_name`, the composed value is validated by glide-core. Note the resolved library name is visible to anyone who can run `CLIENT LIST`/`CLIENT INFO` and may appear in server logs, so do not put secrets or sensitive tenant identifiers in it. Preferred over `lib_name` for framework attribution because it preserves GLIDE adoption visibility. |
| `reconnect_attempts`, `reconnect_delay`, `reconnect_delay_max` | Connection retry strategy |
| `read_from` | Read routing: the `Valkey::ReadFrom::*` constants: `PRIMARY`, `PREFER_REPLICA`, `AZ_AFFINITY`, `AZ_AFFINITY_REPLICAS_AND_PRIMARY`.`AZ_AFFINITY`/`AZ_AFFINITY_REPLICAS_AND_PRIMARY` require `client_az` to also be set. |
| `client_az` | Availability-zone identifier for `AZ_AFFINITY` / `AZ_AFFINITY_REPLICAS_AND_PRIMARY` routing (e.g. `"us-west-2a"`) |
| `inflight_requests_limit`  | Maximum concurrent in-flight requests (non-negative integer) |
| `lazy_connect` | Delay the actual connection until the first command is sent |
| `periodic_checks` | Cluster topology health checks: `{ manual_interval: { duration_in_sec: N } }` or `{ disabled: true }`. Accepted (as a no-op) on standalone connections. |

## Forking Support

A Ruby client currently have limited forking support. After each fork you need to recreate the Valkey instance.

> **Note:** if the parent issues any command before forking, a client created in
> the child can still be killed by a native signal. This is a limitation of the
> Rust core, tracked in [valkey-glide#6912](https://github.com/valkey-io/valkey-glide/pull/6912). Until
> it ships, do not use Valkey in the parent process.

## Building and Testing

For AI-assisted development, see [AGENTS.md](./AGENTS.md) and [CLAUDE.md](./CLAUDE.md).

Contributing: [CONTRIBUTING.md](./CONTRIBUTING.md).

For setting up your local development, see [DEVELOPER.md](./DEVELOPER.md)

## Community and Feedback

Join the community on Valkey Slack to ask questions and share feedback: [Join Valkey Slack](https://join.slack.com/t/valkey-oss-developer/shared_invite/zt-2nxs51chx-EB9hu9Qdch3GMfRcztTSkQ).

Report issues: [valkey-glide-ruby issues](https://github.com/valkey-io/valkey-glide-ruby/issues).

## License

Apache-2.0. See [LICENSE](https://github.com/valkey-io/valkey-glide-ruby/blob/main/LICENSE) in the repository.
