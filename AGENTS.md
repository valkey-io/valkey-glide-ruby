# AGENTS: Ruby Client Context for Agentic Tools

This file provides AI agents and developers with the minimum but sufficient context to work productively with the Valkey GLIDE Ruby client (`valkey-rb`). It covers build commands, testing, contribution requirements, and essential guardrails specific to the Ruby implementation.

## Repository Overview

This is the **Ruby client** for Valkey GLIDE, published as the `valkey-rb` gem. It provides a synchronous, redis-rb-compatible API on top of the Rust GLIDE core via FFI.

**Primary Languages:** Ruby, Rust (FFI native library, built separately from [valkey-glide](https://github.com/valkey-io/valkey-glide))

**Build System:** Bundler, Rake, RubyGems

**Architecture:** Ruby wrapper around `glide-ffi` (`libglide_ffi.so` / `.dylib`) — same FFI path as Go and Python sync clients

**Key Components:**

- `lib/valkey.rb` — Main client, pipelining, response conversion
- `lib/valkey/bindings.rb` — FFI bindings
- `lib/valkey/commands/` — Command modules
- `lib/valkey/opentelemetry.rb` — Native OTel configuration
- `test/valkey/` — Standalone integration tests
- `test/cluster/` — Cluster integration tests
- `test/lint/` — redis-rb compatibility lint suites

## Architecture Quick Facts

**Core Implementation:** Ruby wrapper around glide-core via `glide-ffi` cdylib

**Client Types:** `Valkey` — standalone or cluster (`cluster_mode: true`)

**API Style:** Synchronous, blocking calls (redis-rb style)

**Communication:** Direct FFI (`Bindings.command`, `Bindings.batch`)

**Supported Platforms:**

- Linux: Ubuntu 20+, Amazon Linux 2/2023 (x86_64, aarch64)
- macOS: 13.7+ (x86_64), 14.7+ (aarch64)
- **Note:** Alpine Linux / MUSL is **not** supported

**Ruby Versions:** 2.6, 2.7, 3.0, 3.1, 3.2, 3.3, 3.4, JRuby (CI matrix)

**Gem name:** `valkey-rb` on RubyGems

## Build and Test Rules (Agents)

### Preferred (Bundler / Rake)

```bash
# Setup
bin/setup                              # bundle install

# Linting
bundle exec rubocop

# Testing
bundle exec rake test                  # standalone (default)
bundle exec rake test:valkey           # standalone explicitly
bundle exec rake test:cluster          # cluster (needs nodes 7000-7005)

# Verbose / CI mode
CI=1 bundle exec rake test:valkey

# Console
bundle exec bin/console
```

### Raw Equivalents

```bash
# Run a single test file
bundle exec ruby test/valkey/string_commands_test.rb

# Run with custom port
VALKEY_PORT=6379 TIMEOUT=10 bundle exec rake test:valkey

# Load gem from lib/ without install
RUBYOPT="-I$(pwd)/lib" ruby -r valkey -e 'p Valkey.new.ping'
```

### Test Prerequisites

| Suite | Server requirement |
|-------|-------------------|
| `test:valkey` | Standalone Valkey/Redis on `localhost:6379` (DB 15) |
| `test:cluster` | 6-node cluster on `127.0.0.1:7000`–`7005` |
| SSL tests | TLS Valkey on port `6380` + certs in `test/fixtures/ssl/` |
| Module tests | JSON, Bloom, Search modules loaded (see CI workflow) |

### Rebuild Native FFI (when changing glide-core)

```bash
cd /path/to/valkey-glide/ffi
cargo build --release
cp target/release/libglide_ffi.so /path/to/valkey-glide-ruby/lib/valkey/   # Linux
# cp target/release/libglide_ffi.dylib ...                                   # macOS
```

## Contribution Requirements

### Developer Certificate of Origin (DCO) Signoff REQUIRED

All commits must include a `Signed-off-by` line (per [valkey-glide CONTRIBUTING](https://github.com/valkey-io/valkey-glide/blob/main/CONTRIBUTING.md)):

```bash
git commit -s -m "feat(ruby): add new command implementation"
git config --global format.signOff true
```

### Conventional Commits

```
<type>(<scope>): <description>
```

**Example:** `feat(ruby): implement CLUSTER SCAN with routing options`

**Scopes:** `ruby`, or command family name when appropriate.

### Code Quality Requirements

**RuboCop (required before commit):**

```bash
bundle exec rubocop
bundle exec rubocop -A   # auto-correct safe offenses
```

**Rust FFI (when updating native library):**

```bash
cd valkey-glide/ffi
cargo clippy --all-features --all-targets -- -D warnings
cargo fmt --manifest-path ./Cargo.toml --all
```

## Guardrails & Policies

### Generated Outputs (Never Commit)

- `*.gem` — built gem packages
- `coverage/` — coverage reports
- `tmp/`, `test/tmp/` — temporary test artifacts
- Regenerated SSL certs unless intentionally updated (`test/fixtures/ssl/*.pem` may be committed for CI)
- Wrong-platform `libglide_ffi` binaries (build per OS/arch)

### Ruby-Specific Rules

- **Ruby 2.6+ Required:** Minimum per `valkey.gemspec`
- **FFI dependency:** `ffi ~> 1.17.0` — do not break ABI without rebuilding native lib
- **Synchronous only:** No async client in this repo; do not add EventMachine/async patterns without design review
- **redis-rb compatibility:** Prefer matching redis-rb method signatures and return types when implementing commands
- **Command args:** All FFI args are strings; convert types in Ruby before `send_command`
- **Pipeline transactions:** `MULTI`/`EXEC`/`DISCARD` in `pipelined` use sequential fallback — do not remove without fixing FFI batch stability
- **OpenTelemetry:** Init once per process via `Valkey::OpenTelemetry.init`; spans created in FFI layer

### Command Implementation Guidelines

1. Check `RequestType` in `lib/valkey/request_type.rb` against glide-core `request_type.rs`
2. Add method to appropriate `lib/valkey/commands/*.rb` module
3. Use `send_command(RequestType::..., args)` 
4. Add tests: `test/valkey/` + `test/lint/` when applicable
5. Document with YARD comments + Valkey command link

### Never Commit

- Secrets, `.env` credentials, production URLs
- Debug `puts` in production code paths (PubSub callback is intentional for now)

## Project Structure (Essential)

```text
valkey-glide-ruby/
├── lib/valkey.rb
├── lib/valkey/
│   ├── bindings.rb
│   ├── libglide_ffi.{so,dylib}
│   ├── commands/*.rb
│   ├── opentelemetry.rb
│   ├── pipeline.rb
│   ├── request_type.rb
│   └── response_type.rb
├── test/valkey/          # standalone tests
├── test/cluster/         # cluster tests
├── test/lint/            # shared lint
├── valkey.gemspec
├── Rakefile
└── .github/workflows/CI.yml
```

## Quality Gates (Agent Checklist)

- [ ] `bundle exec rubocop` passes
- [ ] `bundle exec rake test:valkey` passes (with Valkey running)
- [ ] `bundle exec rake test:cluster` passes (if cluster commands touched)
- [ ] New commands have tests in `test/valkey/` and lint coverage where applicable
- [ ] `RequestType` matches glide-core enum
- [ ] No secrets or generated junk committed
- [ ] DCO signoff: `git log --format="%B" -n 1 | grep "Signed-off-by"`
- [ ] Conventional commit format used
- [ ] README / DEVELOPER.md updated if public API or setup changed
- [ ] Native lib rebuilt and copied if FFI/protobuf changed upstream

## Quick Facts for Reasoners

**Package:** `valkey-rb` on RubyGems  
**API Style:** Synchronous, redis-rb-compatible  
**Client:** `Valkey.new` — standalone or `cluster_mode: true`  
**Key Features:** Pipelining, OpenTelemetry (native), statistics, TLS, URL parsing, cluster routing  
**Testing:** Minitest + rake tasks; lint suites for redis-rb parity  
**Core repo:** [valkey-glide](https://github.com/valkey-io/valkey-glide) (`ffi/`, `glide-core/`)  
**This repo:** [valkey-glide-ruby](https://github.com/valkey-io/valkey-glide-ruby)

## If You Need More

- **Getting Started:** [README.md](./README.md)
- **Contributing:** [CONTRIBUTING.md](./CONTRIBUTING.md)
- **Examples:** [examples/](./examples/)
- **Development Setup:** [DEVELOPER.md](./DEVELOPER.md)
- **Claude-specific rules:** [CLAUDE.md](./CLAUDE.md)
- **Command coverage:** [Wiki — implementation status](https://github.com/valkey-io/valkey-glide-ruby/wiki/The-implementation-status-of-the-Valkey-commands)
- **GLIDE docs:** [glide.valkey.io](https://glide.valkey.io/)
- **Upstream FFI:** [valkey-glide/ffi](https://github.com/valkey-io/valkey-glide/tree/main/ffi)
- **Other language AGENTS.md:** [valkey-glide/python/AGENTS.md](https://github.com/valkey-io/valkey-glide/blob/main/python/AGENTS.md), [java/AGENTS.md](https://github.com/valkey-io/valkey-glide/blob/main/java/AGENTS.md)
