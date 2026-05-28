# Developer Guide

This document describes how to set up your development environment to build and test the Valkey GLIDE Ruby client (`valkey-rb`).

## Development Overview

The Valkey GLIDE Ruby client consists of **Ruby** application code and a **Rust FFI** native library. Ruby talks to [glide-core](https://github.com/valkey-io/valkey-glide/tree/main/glide-core) through the [`glide-ffi`](https://github.com/valkey-io/valkey-glide/tree/main/ffi) crate, exposed as `libglide_ffi.so` (Linux) or `libglide_ffi.dylib` (macOS) via the [`ffi`](https://github.com/ffi/ffi) gem.

| Layer | Technology | Location |
|-------|------------|----------|
| Application API | Ruby | `lib/valkey.rb`, `lib/valkey/commands/` |
| FFI bindings | Ruby FFI | `lib/valkey/bindings.rb` |
| Native bridge | Rust `cdylib` | `lib/valkey/libglide_ffi.{so,dylib}` |
| Core driver | Rust `glide-core` | Built from [valkey-glide](https://github.com/valkey-io/valkey-glide) |

This architecture matches the **Go** and **Python sync** clients (C FFI), not the Java (JNI) or Python async (PyO3 + UDS) stacks.

## Project Structure

```text
valkey-glide-ruby/
├── lib/
│   ├── valkey.rb                 # Client, pipelining, response conversion
│   ├── valkey/
│   │   ├── bindings.rb           # FFI definitions
│   │   ├── libglide_ffi.so       # Prebuilt Linux native library
│   │   ├── libglide_ffi.dylib    # Prebuilt macOS native library
│   │   ├── commands/             # Command modules per data type
│   │   ├── opentelemetry.rb      # OTel init and sampling
│   │   ├── pipeline.rb           # Pipeline helper
│   │   ├── request_type.rb       # Command enum (maps to glide-core)
│   │   ├── response_type.rb      # Response enum
│   │   └── errors.rb             # Ruby exception types
├── test/
│   ├── valkey/                   # Standalone server tests
│   ├── cluster/                  # Cluster tests
│   ├── lint/                     # Shared lint suites
│   └── support/helper/           # Test helpers (client, cluster, SSL)
├── bin/
│   ├── setup                     # bundle install
│   └── console                   # IRB with gem loaded
├── .github/workflows/CI.yml      # RuboCop + test matrix
├── valkey.gemspec
├── Gemfile
└── Rakefile                      # test:valkey, test:cluster
```

## Prerequisites

### Software Dependencies

- **Ruby** 2.6+ (3.x recommended for development)
- **Bundler**
- **git**
- **Valkey** or Redis OSS (for integration tests)
- **Docker** (optional; matches CI setup)

To **rebuild** the native FFI library from source:

- **Rust** (`rustup`)
- **GCC** / Xcode command-line tools
- **cmake**, **pkg-config**, **openssl** / **libssl-dev**
- Clone of [valkey-glide](https://github.com/valkey-io/valkey-glide) at a compatible release tag

### Valkey Installation

See the [Valkey installation guide](https://valkey.io/topics/installation/) to install `valkey-server` and `valkey-cli`.

**Ubuntu / Debian (standalone testing):**

```bash
sudo apt update -y
sudo apt install -y ruby-full build-essential
```

**macOS:**

```bash
brew install ruby
```

## Clone and Local Setup

```bash
git clone https://github.com/valkey-io/valkey-glide-ruby.git
cd valkey-glide-ruby
bin/setup   # runs bundle install
```

Load the gem from the checkout without installing:

```bash
export RUBYOPT="-I$(pwd)/lib"
bundle exec ruby -r valkey -e 'puts Valkey::VERSION'
```

Interactive console:

```bash
bundle exec bin/console
```

## Build Native FFI from Source

The published gem includes prebuilt `libglide_ffi` binaries. To update them from [valkey-glide](https://github.com/valkey-io/valkey-glide):

```bash
VERSION=main   # or a release tag, e.g. v2.4.0
git clone --branch ${VERSION} https://github.com/valkey-io/valkey-glide.git
cd valkey-glide/ffi

# Install Rust if needed
# curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

cargo build --release
```

Copy the built library into the Ruby gem:

```bash
# Linux
cp target/release/libglide_ffi.so /path/to/valkey-glide-ruby/lib/valkey/

# macOS
cp target/release/libglide_ffi.dylib /path/to/valkey-glide-ruby/lib/valkey/
```

Verify the gem loads the new library:

```bash
cd /path/to/valkey-glide-ruby
bundle exec ruby -e 'require "valkey"; c = Valkey.new; puts c.ping; c.close'
```

### Rust Linters (when changing FFI)

From `valkey-glide/ffi/`:

```bash
rustup component add clippy rustfmt
cargo clippy --all-features --all-targets -- -D warnings
cargo fmt --manifest-path ./Cargo.toml --all
```

See [ffi/README.md](https://github.com/valkey-io/valkey-glide/blob/main/ffi/README.md) in valkey-glide for C header generation (`cbindgen`) if needed.

## Running Tests

Tests use **Minitest**. The suite is split into standalone (`test/valkey/`) and cluster (`test/cluster/`) groups.

### Start Valkey (standalone)

Default test configuration (see `test/test_helper.rb`):

| Variable | Default | Purpose |
|----------|---------|---------|
| `VALKEY_PORT` | `6379` | Plain TCP |
| `VALKEY_SSL_PORT` | `6380` | TLS (optional) |
| `TIMEOUT` | `5.0` | Client timeout |
| DB | `15` | Test database |

```bash
# Example: Docker standalone (matches CI)
docker run -d --name valkey-test -p 6379:6379 valkey/valkey:8 \
  valkey-server --enable-module-command yes
```

### Start Valkey Cluster

Cluster tests expect six nodes on `127.0.0.1:7000`–`7005`. CI uses `grokzen/redis-cluster:7.0.15`.

```bash
docker run -d --name redis-cluster -p 7000-7005:7000-7005 grokzen/redis-cluster:7.0.15
```

### Run Tests

```bash
# All default (standalone) tests
bundle exec rake test
# or
bundle exec rake test:valkey

# Cluster tests only
bundle exec rake test:cluster

# Verbose output (also enabled when CI=1)
CI=1 bundle exec rake test:valkey
```

### SSL Tests

Generate test certificates:

```bash
ruby test/fixtures/ssl/generate_certs.rb
```

Start TLS Valkey on port 6380 (see `.github/workflows/CI.yml` for a full Docker example).

### Module Tests (JSON, Bloom, Search)

CI copies prebuilt modules into `test/fixtures/`:

- `redisjson.so` — JSON commands
- `redisbloom.so` — Bloom filters
- `redisearch.so` — Vector / FT commands

Load modules when starting Valkey if you run module-specific tests locally.

### Environment Overrides

```bash
VALKEY_PORT=6379 TIMEOUT=10 bundle exec rake test:valkey
```

## Linters

### RuboCop

```bash
bundle exec rubocop
```

CI runs RuboCop on every push and pull request (see `.github/workflows/CI.yml`).

Auto-correct safe offenses:

```bash
bundle exec rubocop -A
```

Configuration: `.rubocop.yml`, `.rubocop_todo.yml`.

## Contributing New Valkey Commands

When adding a command, check whether it already exists in [glide-core](https://github.com/valkey-io/valkey-glide/blob/main/glide-core/src/request_type.rs) and [command_request.proto](https://github.com/valkey-io/valkey-glide/blob/main/glide-core/src/protobuf/command_request.proto). Other language clients (Python, Java, Go) are the reference for semantics and routing.

### Steps

1. **Add `RequestType` constant** in `lib/valkey/request_type.rb` if not present (must match glide-core enum).
2. **Implement the command** in the appropriate file under `lib/valkey/commands/` (e.g. `string_commands.rb`, `hash_commands.rb`).
3. **Use `send_command`** with the correct `RequestType` and argument list (all arguments converted to strings for FFI).
4. **Add standalone tests** in `test/valkey/<group>_commands_test.rb`.
5. **Add lint tests** in `test/lint/<group>_commands.rb` when the command should match redis-rb behavior.
6. **Update the wiki** [command implementation status](https://github.com/valkey-io/valkey-glide-ruby/wiki/The-implementation-status-of-the-Valkey-commands).

### Command module layout

| Module file | Valkey command families |
|-------------|-------------------------|
| `string_commands.rb` | Strings, counters |
| `hash_commands.rb` | Hashes |
| `list_commands.rb` | Lists |
| `set_commands.rb` | Sets |
| `sorted_set_commands.rb` | Sorted sets |
| `stream_commands.rb` | Streams |
| `bitmap_commands.rb` | Bitmaps |
| `hyper_log_log_commands.rb` | HyperLogLog |
| `geo_commands.rb` | Geo |
| `generic_commands.rb` | Keys, scan, type, … |
| `connection_commands.rb` | Connection, auth, select |
| `server_commands.rb` | Server, config, ACL |
| `scripting_commands.rb` | Lua scripting |
| `function_commands.rb` | Functions |
| `transaction_commands.rb` | MULTI, WATCH, … |
| `pubsub_commands.rb` | Pub/Sub |
| `cluster_commands.rb` | Cluster administration |
| `json_commands.rb` | RedisJSON / Valkey JSON |
| `vector_search_commands.rb` | RediSearch / FT |
| `module_commands.rb` | MODULE |

### Tests

- **Unit-style command tests**: `test/valkey/*_test.rb` — require a running server.
- **Lint suites**: `test/lint/*.rb` — included from valkey and cluster tests for API parity checks.
- **OpenTelemetry**: `test/valkey/test_opentelemetry.rb` — uses file exporter endpoints.
- **Statistics**: `test/valkey/test_statistics.rb`.

### Documentation in code

Follow existing YARD-style comments in command modules: link to [valkey.io/commands](https://valkey.io/commands/), document parameters and return types, note cluster vs standalone behavior.

## OpenTelemetry Development

OpenTelemetry is configured via `Valkey::OpenTelemetry.init` before client creation. Sampling is applied in Ruby (`should_sample?`); spans are created in FFI (`create_otel_span`, `create_batch_otel_span`).

File exporter example for local debugging:

```ruby
Valkey::OpenTelemetry.init(
  traces: { endpoint: "file:///tmp/valkey_traces.json", sample_percentage: 100 },
  metrics: { endpoint: "file:///tmp/valkey_metrics.json" }
)
```

Run OTel tests:

```bash
bundle exec ruby test/valkey/test_opentelemetry.rb
```

## CI Overview

GitHub Actions (`.github/workflows/CI.yml`):

| Job | Matrix |
|-----|--------|
| `lint` | Ruby 3.3, RuboCop |
| `standalone` | Ruby 2.6–3.4 + JRuby; Valkey 7.2, 8, 8.1 |
| `cluster` | Ruby 2.6–3.4; grokzen/redis-cluster |

## Packaging

Release artifacts are built via `valkey.gemspec`:

- Native libraries under `lib/valkey/` are included in the gem.
- Test files, `bin/`, and `.github/` are excluded from the release.

Build locally:

```bash
gem build valkey.gemspec
gem install ./valkey-rb-*.gem
```

## Troubleshooting

| Problem | Suggestion |
|---------|------------|
| `CannotConnectError` | Ensure Valkey is running on the configured host/port; cluster requires all seed nodes. |
| `LoadError` / FFI library not found | Confirm `lib/valkey/libglide_ffi.{so,dylib}` exists and matches your OS/arch. |
| Wrong architecture after FFI rebuild | Rebuild `glide-ffi` on the target platform; do not copy Linux `.so` to macOS. |
| Cluster tests flaky | Wait for `cluster_state:ok`; increase `TIMEOUT` env var. |
| SSL test failures | Regenerate certs: `ruby test/fixtures/ssl/generate_certs.rb`. |
| Pipeline / MULTI crashes | Transaction commands in `pipelined` use sequential fallback by design. |

## Recommended Editor Extensions

- [Ruby LSP](https://marketplace.visualstudio.com/items?itemName=Shopify.ruby-lsp) or [Solargraph](https://marketplace.visualstudio.com/items?itemName=castwide.solargraph)
- [RuboCop](https://marketplace.visualstudio.com/items?itemName=rubocop.vscode-rubocop)
- [rust-analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer) — when editing valkey-glide FFI

## Examples

Sample scripts live in [examples/](./examples/). Run from the repo root:

```bash
bundle exec ruby examples/standalone.rb
```

See [examples/README.md](./examples/README.md) for Docker setup and environment variables.

## Community and Feedback

Join Valkey Slack: [Join Valkey Slack](https://join.slack.com/t/valkey-oss-developer/shared_invite/zt-2nxs51chx-EB9hu9Qdch3GMfRcztTSkQ).

Contribution guidelines: [CONTRIBUTING.md](./CONTRIBUTING.md). Broader GLIDE process: [valkey-glide CONTRIBUTING.md](https://github.com/valkey-io/valkey-glide/blob/main/CONTRIBUTING.md).
