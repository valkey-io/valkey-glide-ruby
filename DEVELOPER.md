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
│   └── valkey/
│       ├── bindings.rb           # FFI definitions
│       ├── native/               # Platform-specific native libraries (in gem)
│       │   ├── x86_64-unknown-linux-gnu/
│       │   └── aarch64-unknown-linux-gnu/
│       ├── commands/             # Command modules per data type
│       ├── opentelemetry.rb      # OTel init and sampling
│       ├── pipeline.rb           # Pipeline helper
│       ├── request_type.rb       # Command enum (maps to glide-core)
│       ├── response_type.rb      # Response enum
│       └── errors.rb             # Ruby exception types
├── valkey-glide/                 # Git submodule (valkey-io/valkey-glide)
│   └── ffi/                      # Rust FFI crate (build target)
├── test/
│   ├── valkey/                   # Standalone server tests
│   ├── cluster/                  # Cluster tests
│   ├── lint/                     # Shared lint suites
│   └── support/helper/           # Test helpers (client, cluster, SSL)
├── bin/
│   ├── setup                     # bundle install
│   └── console                   # IRB with gem loaded
├── .github/workflows/
│   ├── CI.yml                    # RuboCop + test matrix
│   └── cd.yml                    # Build and publish gem
├── valkey.gemspec
├── Gemfile
└── Rakefile                      # test:standalone, test:cluster, native:build
```

## Prerequisites

### Software Dependencies

- **Ruby** 2.6+ (3.x recommended for development)
- **Bundler**
- **git**
- **Valkey** or Redis OSS (for integration tests)
- **Docker** (optional; only needed for module tests with `valkey-bundle` image)

To **build** the native FFI library from source:

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
git clone --recurse-submodules https://github.com/valkey-io/valkey-glide-ruby.git
cd valkey-glide-ruby
bin/setup   # runs bundle install
```

If you've already cloned without submodules:

```bash
git submodule update --init --recursive
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

This repository includes [valkey-glide](https://github.com/valkey-io/valkey-glide) as a Git submodule. Rake tasks are provided to build the native FFI library.

### Prerequisites for Building

- **Rust toolchain**: Install via [rustup](https://rustup.rs/)
- **Protobuf compiler**: `protoc` (required for glide-core)

### Build with Rake

```bash
# Build the native FFI library (release mode)
rake native:build

# This will:
# 1. Initialize the valkey-glide submodule if needed
# 2. Build the Rust FFI library in release mode
# 3. Output: valkey-glide/ffi/target/release/libglide_ffi.{so,dylib}
```

### Available Rake Tasks

| Task | Description |
|------|-------------|
| `rake native:build` | Build the native FFI library (release mode) |
| `rake native:build_debug` | Build the native FFI library (debug mode) |
| `rake native:clean` | Clean native build artifacts |
| `rake native:submodule` | Initialize/update the valkey-glide submodule |
| `rake native:package` | Copy built library to `lib/valkey/native/{platform}/` for gem packaging |

### Verify the Build

```bash
bundle exec ruby -e 'require "valkey"; c = Valkey.new; puts c.ping; c.close'
```

### Updating the Submodule

To update to a newer version of valkey-glide:

```bash
cd valkey-glide
git fetch origin
git checkout v2.4.0  # or desired tag/branch
cd ..
git add valkey-glide
git commit -m "Update valkey-glide submodule to v2.4.0"

# Rebuild the native library
rake native:build
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
| `TLS_CERT_DIR` | `valkey-glide/utils/tls_crts` | Path to TLS certs (set by CI) |
| `TIMEOUT` | `5.0` | Client timeout |
| DB | `15` | Test database |

```bash
# Preferred: use cluster_manager.py (same as CI and all other GLIDE clients)
python3 valkey-glide/utils/cluster_manager.py start -r 0 -p 6379 --prefix standalone

# Alternative: Docker standalone
docker run -d --name valkey-test -p 6379:6379 valkey/valkey:8 valkey-server
```

### Start Valkey Cluster

Cluster tests auto-start via `cluster_manager.py` (the `TestCluster` class handles lifecycle).
You can also start manually:

```bash
python3 valkey-glide/utils/cluster_manager.py start --cluster-mode --prefix cluster
```

### Run Tests

```bash
# All default (standalone) tests
bundle exec rake test
# or
bundle exec rake test:standalone

# Cluster tests only
bundle exec rake test:cluster

# Verbose output (also enabled when CI=1)
CI=1 bundle exec rake test:standalone
```

### SSL Tests

The preferred approach (matching CI and all other GLIDE clients) uses `cluster_manager.py`:

```bash
# Start a TLS-only server on port 6380 (generates certs in valkey-glide/utils/tls_crts/)
python3 valkey-glide/utils/cluster_manager.py --tls start -r 0 -p 6380 --prefix tls-standalone

# Point tests at the generated certs
export TLS_CERT_DIR=$(pwd)/valkey-glide/utils/tls_crts

# Run tests
bundle exec rake test:standalone

# Stop the TLS server
python3 valkey-glide/utils/cluster_manager.py --tls stop --prefix tls-standalone
```

Alternatively, for local development without Python, generate certs and start manually:

```bash
ruby test/fixtures/ssl/generate_certs.rb
# Then start a TLS Valkey server on port 6380 using those certs
```

### Module Tests (JSON, Bloom, Search)

CI uses the shared `start-valkey-docker` action with `valkey/valkey-bundle:9.1` (modules pre-loaded).
Tests connect via `STANDALONE_ENDPOINTS` env var.

Load modules when starting Valkey if you run module-specific tests locally.

### Environment Overrides

```bash
VALKEY_PORT=6379 TIMEOUT=10 bundle exec rake test:standalone
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

## Building the Gem Locally

The gem includes platform-specific native libraries. For development and testing, you can build a gem that works on your current platform.

### Quick Build (Current Platform Only)

```bash
# 1. Build the native FFI library
rake native:build

# 2. Package it into lib/valkey/native/{platform}/
rake native:package

# 3. Build the gem
gem build valkey.gemspec

# 4. Install locally
gem install ./valkey-rb-*.gem
```

### What `rake native:package` Does

This task copies the built native library to the correct platform-specific directory:

```text
lib/valkey/native/
├── x86_64-unknown-linux-gnu/
│   └── libglide_ffi.so
├── aarch64-unknown-linux-gnu/
│   └── libglide_ffi.so
├── x86_64-apple-darwin/
│   └── libglide_ffi.dylib
└── aarch64-apple-darwin/
    └── libglide_ffi.dylib
```

The gem automatically detects your platform at runtime and loads the appropriate library.

### Building for Multiple Platforms

For distribution, you need native libraries for each target platform. The CD workflow builds these using GitHub Actions runners:

- **x86_64-unknown-linux-gnu** — Ubuntu x64 runner
- **aarch64-unknown-linux-gnu** — Ubuntu ARM64 runner

To build for a different platform, you must build on that platform (or use cross-compilation tools).

### Verify the Gem Contents

```bash
# Unpack and inspect
gem unpack valkey-rb-*.gem --target=gem-contents
find gem-contents -name "libglide_ffi.*"

# Or list files in the gem
gem spec valkey-rb-*.gem files
```

### Install and Test

```bash
# Install the locally built gem
gem install ./valkey-rb-*.gem

# Test it works (requires Valkey running)
ruby -e "require 'valkey'; c = Valkey.new; puts c.ping; c.close"
```

### Troubleshooting Gem Builds

| Problem | Solution |
|---------|----------|
| `LoadError: Could not find libglide_ffi` | Run `rake native:package` before `gem build` |
| Wrong platform library | Rebuild on the target platform; don't copy between OS/arch |
| Gem too large | Check that `valkey-glide/` submodule isn't included (gemspec excludes it) |
| Version mismatch | Update `lib/valkey/version.rb` before building |

## Troubleshooting

| Problem | Suggestion |
|---------|------------|
| `CannotConnectError` | Ensure Valkey is running on the configured host/port; cluster requires all seed nodes. |
| `LoadError` / FFI library not found | Confirm `lib/valkey/libglide_ffi.{so,dylib}` exists and matches your OS/arch. |
| Wrong architecture after FFI rebuild | Rebuild `glide-ffi` on the target platform; do not copy Linux `.so` to macOS. |
| Cluster tests flaky | Wait for `cluster_state:ok`; increase `TIMEOUT` env var. |
| SSL test failures | Use `cluster_manager.py --tls` (see SSL Tests above), or regenerate local certs: `ruby test/fixtures/ssl/generate_certs.rb`. |
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
