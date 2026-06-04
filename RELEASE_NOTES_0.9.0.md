# Valkey GLIDE Ruby v0.9.0 — Developer Preview

We're excited to announce the first developer preview release of **Valkey GLIDE for Ruby** (`valkey-glide-rb`).

## What is Valkey GLIDE Ruby?

Valkey GLIDE Ruby is the official Ruby client for [Valkey](https://valkey.io), built on the same high-performance Rust core as the Python, Java, Node.js, and Go GLIDE clients. It provides a **redis-rb compatible API** while delivering GLIDE's reliability and performance.

## Features

- **High-performance Rust core** — Same battle-tested [valkey-glide](https://github.com/valkey-io/valkey-glide) FFI layer as other GLIDE clients
- **redis-rb compatible API** — Familiar `Valkey.new`, command methods, `pipelined`, URL parsing
- **Standalone and Cluster mode** support
- **TLS/SSL** connections with certificate configuration
- **Native OpenTelemetry** tracing and metrics (configured in Rust core)
- **Client statistics** for monitoring connections and operations
- **Comprehensive command coverage**:
  - Strings, Hashes, Lists, Sets, Sorted Sets, Streams
  - Transactions (MULTI/EXEC) and Pipelining
  - Lua scripting (EVAL, EVALSHA)
  - Cluster commands
  - JSON commands (RedisJSON/Valkey JSON module)
  - Vector search commands (RediSearch module)
  - PubSub (publish, pubsub_channels, etc.)
  - ACL commands

## Supported Platforms

- Linux (x86_64, aarch64)

**Note:** macOS native libraries are not yet included in the gem. Alpine Linux (MUSL) is not yet supported.

## Documentation

- [README](https://github.com/valkey-io/valkey-glide-ruby/blob/main/README.md)
- [Developer Guide](https://github.com/valkey-io/valkey-glide-ruby/blob/main/DEVELOPER.md)
- [Command Coverage Wiki](https://github.com/valkey-io/valkey-glide-ruby/wiki/The-implementation-status-of-the-Valkey-commands)
- [Examples](https://github.com/valkey-io/valkey-glide-ruby/tree/main/examples)

## Feedback

We'd love your feedback! Please report issues and share your experience:

- [GitHub Issues](https://github.com/valkey-io/valkey-glide-ruby/issues)
- [Valkey Slack](https://join.slack.com/t/valkey-oss-developer/shared_invite/zt-2nxs51chx-EB9hu9Qdch3GMfRcztTSkQ)
