# AGENTS: Ruby Client Context for Agentic Tools

This file provides AI agents and developers with the minimum but sufficient context to work productively with the Valkey GLIDE Ruby client (`valkey-glide-rb`). It covers build commands, testing, contribution requirements, and essential guardrails specific to the Ruby implementation.

## Repository Overview

This is the **Ruby client** for Valkey GLIDE, published as the `valkey-glide-rb` gem. It provides a synchronous API on top of the Rust GLIDE core via FFI.

**Primary Languages:** Ruby, Rust (FFI native library, built separately from [valkey-glide](https://github.com/valkey-io/valkey-glide))

**Build System:** Bundler, Rake, RubyGems

**Architecture:** Ruby wrapper around `glide-ffi` (`libglide_ffi.so` / `.dylib`), the same FFI path as Go and Python sync clients

**Key Components:**

- `lib/valkey.rb`: Main client, pipelining, response conversion
- `lib/valkey/bindings.rb`: FFI bindings
- `lib/valkey/commands/`: Command modules
- `lib/valkey/opentelemetry.rb`: Native OTel configuration
- `test/unit/`: Server-free unit tests
- `test/integration/standalone/`: Standalone integration tests
- `test/integration/cluster/`: Cluster integration tests
- `test/integration/valkey/`: Shared valkey-glide-specific test modules
- `test/lint/`: Lint suites

## Architecture Quick Facts

**Core Implementation:** Ruby wrapper around glide-core via `glide-ffi` cdylib

**Client Types:** `Valkey`, standalone or cluster (`cluster_mode: true`)

**API Style:** Synchronous, blocking calls.

**Communication:** Direct FFI (`Bindings.command`, `Bindings.batch`)

**Supported Platforms:**

- Linux: Ubuntu 20+, Amazon Linux 2/2023 (x86_64, aarch64)
- Alpine Linux 3.18+ (x86_64, aarch64), musl libc
- macOS: 13.7+ (x86_64), 14.7+ (aarch64)

**Ruby Versions:** 3.0, 3.1, 3.2, 3.3, 3.4. Minimum is 3.0 per `valkey.gemspec`.

**Gem name:** `valkey-glide-rb` on RubyGems

## Context Retrieval

When working on a feature, read these paths first:

| Topic | Read first |
|-------|------------|
| Connection / options | `lib/valkey.rb` (`#initialize`), `test/lint/connection_options.rb` |
| New command | `lib/valkey/request_type.rb`, matching `lib/valkey/commands/*.rb`, `test/lint/*` |
| Pipelining / batch | `lib/valkey.rb` (`pipelined`, `send_batch_commands`), `lib/valkey/pipeline.rb` |
| OpenTelemetry | `lib/valkey/opentelemetry.rb`, `test/integration/valkey/opentelemetry_test.rb` |
| FFI / errors | `lib/valkey/bindings.rb`, `lib/valkey/errors.rb` |
| Cluster | `test/support/helper/cluster.rb`, `test/integration/cluster/` |
| Upstream semantics | [valkey-glide glide-core](https://github.com/valkey-io/valkey-glide/tree/main/glide-core), peer client in `go/` or `python/glide-sync/` |

## Quality Gates (Agent Checklist)

- [ ] Positive tests added.
- [ ] Negative tests covered.
- [ ] `bundle exec rubocop` passes
- [ ] Test servers were started/stopped via `cluster_manager.py` (never hand-launched or ad-hoc `docker run`)
- [ ] `bundle exec rake test:unit` passes (no server needed)
- [ ] `bundle exec rake test:standalone` passes (with Valkey running)
- [ ] `bundle exec rake test:cluster` passes (if cluster commands touched)
- [ ] New commands have tests in `test/integration/valkey/` and lint coverage where applicable
- [ ] `RequestType` matches glide-core enum
- [ ] No secrets or generated junk committed
- [ ] DCO signoff: `git log --format="%B" -n 1 | grep "Signed-off-by"`
- [ ] Conventional commit format used
- [ ] `CHANGELOG.md` updated for user-facing changes
- [ ] PR body follows `.github/pull_request_template.md` (all sections filled, checklist completed)
- [ ] Native lib rebuilt and copied if FFI/protobuf changed upstream

## Build and Test Rules (Agents)

### Preferred (Bundler / Rake)

```bash
# Setup
bin/setup                              # bundle install

# Linting
bundle exec rubocop

# Testing
bundle exec rake test                  # unit + integration
bundle exec rake test:unit             # unit only (no server needed)
bundle exec rake test:integration      # standalone + cluster
bundle exec rake test:standalone       # standalone only
bundle exec rake test:cluster          # cluster only (needs nodes 7000-7005)

# Verbose / CI mode
CI=1 bundle exec rake test:standalone

# Console
bundle exec bin/console
```

### Raw Equivalents

```bash
# Run a single test file
bundle exec ruby -Itest -Ilib test/integration/standalone/commands_test.rb

# Run with custom port
VALKEY_PORT=6379 TIMEOUT=10 bundle exec rake test:standalone

# Load gem from lib/ without install
RUBYOPT="-I$(pwd)/lib" ruby -r valkey -e 'p Valkey.new.ping'
```

### Test Prerequisites

| Suite | Server requirement |
|-------|-------------------|
| `test:standalone` | Standalone Valkey/Redis on `localhost:6379` (DB 15) |
| `test:cluster` | 6-node cluster on `127.0.0.1:7000`-`7005` (auto-started by the suite) |
| SSL tests | TLS Valkey on port `6380` + `export TLS_CERT_DIR=...` (or `SKIP_TLS_TESTS=true`) |
| Module tests | JSON, Bloom, Search modules loaded (see CI workflow) |

### Managing Test Servers

**Prefer `cluster_manager.py` for all test servers.** Start and stop standalone,
TLS, and cluster servers with `valkey-glide/utils/cluster_manager.py`. It's the
same tool CI uses, so ports, the test DB, TLS cert layout, and cluster topology
match CI. Use a manual `valkey-server`/`redis-server` launch or `docker run`
**only** when a scenario cannot be produced with `cluster_manager.py`.

```bash
# Standalone on :6379
python3 valkey-glide/utils/cluster_manager.py start -r 0 -p 6379 --prefix standalone

# TLS on :6380 (generates certs in valkey-glide/utils/tls_crts/)
python3 valkey-glide/utils/cluster_manager.py --tls start -r 0 -p 6380 --prefix tls-standalone
export TLS_CERT_DIR=$(pwd)/valkey-glide/utils/tls_crts   # required for TLS tests

# Stop when done
python3 valkey-glide/utils/cluster_manager.py stop --prefix standalone
python3 valkey-glide/utils/cluster_manager.py --tls stop --prefix tls-standalone
```

### Rebuild Native FFI (when changing glide-core)

Prefer the Rake tasks; they init the submodule and set `GLIDE_NAME=GlideRuby` /
`GLIDE_VERSION` (from `lib/valkey/version.rb`) for `CLIENT SETINFO`:

```bash
rake native:build          # release build in valkey-glide/ffi/target/release/
rake native:build_debug    # debug build
rake native:package        # copy built lib to lib/valkey/native/{arch}-{os}/ for gem packaging
rake native:clean          # cargo clean
```

The client (`lib/valkey/bindings.rb`) loads the native library from the first
location that exists, in this order:

1. `valkey-glide/ffi/target/release/libglide_ffi.{so,dylib}`
2. `valkey-glide/ffi/target/debug/libglide_ffi.{so,dylib}`
3. `lib/valkey/native/{arch}-{os}/libglide_ffi.{so,dylib}` (bundled in the gem)
4. `lib/valkey/libglide_ffi.{so,dylib}` (dev fallback)

Raw equivalent (only if not using Rake):

```bash
# GLIDE_NAME and GLIDE_VERSION are baked in at COMPILE time and reported via
# CLIENT SETINFO (LIB-NAME / LIB-VER). Omitting them yields a library that
# misreports its identity with no error and no local symptom — you would only
# notice by inspecting CLIENT INFO against a live 7.2+ server. Always pass both;
# GLIDE_VERSION must match lib/valkey/version.rb.
#
# Resolve the version from the REPO ROOT, before the cd, and abort if it fails:
# inside valkey-glide/ffi the relative require cannot resolve, and in a
# `VAR=$(...)` form the LoadError would be swallowed, leaving GLIDE_VERSION empty
# — exactly the silent misidentity described above.
GLIDE_VERSION=$(ruby -r./lib/valkey/version -e 'print Valkey::VERSION') || exit 1
[ -n "$GLIDE_VERSION" ] || { echo "could not resolve GLIDE_VERSION" >&2; exit 1; }

cd valkey-glide/ffi
GLIDE_NAME=GlideRuby GLIDE_VERSION="$GLIDE_VERSION" cargo build --release
# release/debug builds under target/ are picked up automatically (order 1-2 above)
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

### Pull Requests REQUIRED

When opening a PR, you MUST follow `.github/pull_request_template.md`. Read that
file first and fill in every section it defines and complete
its Checklist honestly. Do not substitute a free-form description; `gh pr create`
with a custom `--body` bypasses the template, so reproduce the template structure
in the body you pass.

### Changelog REQUIRED

Every user-facing change MUST add an entry to `CHANGELOG.md` under the top
`## 1.x.x (Pending)` section, in the correct subsections.

```markdown
## 1.x.x (Pending)

### Fixes

* fix(ruby): <what changed and the user-visible effect> ([#123](https://github.com/valkey-io/valkey-glide-ruby/issues/123))

### Changes

* feat(ruby): <what changed and the user-visible effect> ([#124](https://github.com/valkey-io/valkey-glide-ruby/pull/124))
```

Each entry follows the same Conventional Commits format as commit messages
(`<type>(<scope>): <description>`, scope `ruby`), states the behavior change,
and links the related issue or PR.

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

- `*.gem`: built gem packages
- `coverage/`: coverage reports
- `tmp/`, `test/tmp/`: temporary test artifacts
- SSL certs: never commit them; TLS tests read certs from `TLS_CERT_DIR` (generated by `cluster_manager.py --tls`)
- Wrong-platform `libglide_ffi` binaries (built per OS/arch during CD into `lib/valkey/native/{arch}-{os}/`)

### Ruby-Specific Rules

- **Ruby 3.0+ Required:** Minimum per `valkey.gemspec`
- **FFI dependency:** `ffi ~> 1.17.0`; do not break ABI without rebuilding native lib
- **Synchronous only:** No async client in this repo; do not add EventMachine/async patterns without design review
- **redis-rb conventions:** Prefer matching redis-rb method signatures and return types when implementing commands for familiarity.
- **Command args:** All FFI args are strings; convert types in Ruby before `send_command`
- **Pipeline transactions:** `MULTI`/`EXEC`/`DISCARD` in `pipelined` use sequential fallback; do not remove without fixing FFI batch stability
- **Pub/Sub:** The public API is currently disabled (`include PubSubCommands` is commented out in `lib/valkey/commands.rb`); Pub/Sub is only partially implemented (see issue #135). Do not re-enable without completing it.
- **OpenTelemetry:** Init once per process via `Valkey::OpenTelemetry.init`; spans created in FFI layer

### Command Implementation Guidelines

1. Check `RequestType` in `lib/valkey/request_type.rb` against glide-core `request_type.rs`
2. Add method to appropriate `lib/valkey/commands/*.rb` module
3. Use `send_command(RequestType::..., args)` 
4. Add tests: `test/integration/valkey/` + `test/lint/` when applicable
5. Document with YARD comments + Valkey command link

### Never Commit

- Secrets, `.env` credentials, production URLs
- Debug `puts` in production code paths (the native Pub/Sub callback in `lib/valkey/glide/pubsub.rb` must never `puts` or block: it runs on a Rust thread under a borrowed GVL)

## Project Structure (Essential)

```text
valkey-glide-ruby/
├── lib/valkey.rb
├── lib/valkey/
│   ├── bindings.rb
│   ├── native/{arch}-{os}/libglide_ffi.{so,dylib}   # bundled per-platform lib (packaged during CD)
│   ├── glide/pubsub.rb   # all Pub/Sub logic; internal, wired into Valkey
│   ├── commands.rb       # requires + includes all command modules
│   ├── commands/*.rb     # 20 command-family modules
│   ├── opentelemetry.rb
│   ├── pipeline.rb
│   ├── request_type.rb
│   └── response_type.rb
├── test/unit/            # server-free unit tests
├── test/integration/
│   ├── standalone/       # standalone tests
│   ├── cluster/          # cluster tests
│   └── valkey/           # shared valkey-glide-specific test modules
├── test/lint/            # shared lint
├── valkey.gemspec
├── Rakefile
└── .github/workflows/ci.yml
```

## Quick Facts for Reasoners

**Package:** `valkey-glide-rb` on RubyGems  
**API Style:** Synchronous. 
**Client:** `Valkey.new`, standalone or `cluster_mode: true`  
**Key Features:** Pipelining, OpenTelemetry (native), statistics, TLS, URL parsing, cluster routing  
**Testing:** Minitest + rake tasks; lint suites.
**Core repo:** [valkey-glide](https://github.com/valkey-io/valkey-glide) (`ffi/`, `glide-core/`)  
**This repo:** [valkey-glide-ruby](https://github.com/valkey-io/valkey-glide-ruby)

## If You Need More

- **Getting Started:** [README.md](./README.md)
- **Contributing:** [CONTRIBUTING.md](./CONTRIBUTING.md)
- **Examples:** [examples/](./examples/)
- **Claude-specific rules:** [CLAUDE.md](./CLAUDE.md)
- **Command coverage:** [Wiki: implementation status](https://github.com/valkey-io/valkey-glide-ruby/wiki/The-implementation-status-of-the-Valkey-commands)
- **GLIDE docs:** [glide.valkey.io](https://glide.valkey.io/)
- **Upstream FFI:** [valkey-glide/ffi](https://github.com/valkey-io/valkey-glide/tree/main/ffi)
