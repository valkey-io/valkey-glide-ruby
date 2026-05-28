# CLAUDE.md

Valkey GLIDE Ruby (`valkey-rb`) is the official Ruby binding for Valkey and Redis OSS. It uses the shared Rust **glide-core** driver via the **glide-ffi** C library, with a redis-rb-compatible Ruby API. This repository is separate from the [valkey-glide](https://github.com/valkey-io/valkey-glide) mono-repo (Python, Java, Node, Go).

## Hard Constraints (non-negotiable)

- NO task completion without tests covering it and passing (when a Valkey server or cluster is available for integration tests)
- NO PR creation without addressing review feedback on tests, docs, and RuboCop
- NEVER assume — verify against `test/valkey/` and `test/lint/` suites
- NEVER ignore bugs, even out of scope — open a GitHub issue on [valkey-glide-ruby](https://github.com/valkey-io/valkey-glide-ruby/issues)

## Rules

### Always

- Direct and concise; no compliments or apologies
- Ask if unsure; stop and reassess if looping
- Match redis-rb conventions when implementing or fixing command APIs
- If asked to do X a certain way, do it that way; disagree in review, do not change without approval

### When Writing

- Commit frequently with meaningful messages; git is our diary
- Focus on **Ruby + FFI** in this repo; core/FFI changes require rebuilding `libglide_ffi` from [valkey-glide/ffi](https://github.com/valkey-io/valkey-glide/tree/main/ffi)
- Keep PRs small and focused
- Update README.md / DEVELOPER.md when changing setup, public API, or test requirements

### Before Task Completion

- Tests cover the change and pass (`bundle exec rake test:valkey` at minimum)
- `bundle exec rubocop` passes for changed Ruby files
- If FFI binary updated, smoke-test: `Valkey.new.ping` on target OS

### Before Push

- `git pull --rebase` on your base branch; resolve conflicts
- Run tests for relevant scope (`test:valkey` and/or `test:cluster`)

### Before PR Creation/Update

- RuboCop clean
- Tests pass for touched areas
- Docs updated if behavior or setup changed
- DCO sign-off on commits (`git commit -s`)

## What the user cares about (all equally important)

- **Performance** — low latency via GLIDE core; avoid unnecessary Ruby allocations in hot paths
- **Reliability** — correct error types (`CommandError`, `ConnectionError`, `TimeoutError`, `CannotConnectError`)
- **Usability** — redis-rb familiarity, clear README and connection options
- **Maintainability** — command modules, lint tests, minimal scope per PR
- **Correctness** — verify with Minitest, not assumptions; compare with other GLIDE clients for semantics

---

## Project Structure

```text
valkey-glide-ruby/
├── lib/valkey.rb              # Client entry: connect, pipeline, convert_response
├── lib/valkey/
│   ├── bindings.rb            # FFI to libglide_ffi
│   ├── libglide_ffi.so|.dylib # Native library (from valkey-glide/ffi)
│   ├── commands/              # One module per command family
│   ├── opentelemetry.rb       # Valkey::OpenTelemetry.init
│   ├── pipeline.rb            # Valkey::Pipeline
│   ├── request_type.rb        # Maps to glide-core RequestType
│   └── response_type.rb       # FFI response decoding
├── test/valkey/                # Standalone integration tests
├── test/cluster/               # Cluster tests
└── test/lint/                  # redis-rb parity lint
```

## Architecture: Ruby to Core

| Component | Mechanism | Native library | Communication |
|-----------|-----------|----------------|---------------|
| Ruby client | FFI gem | `libglide_ffi` (glide-ffi cdylib) | Direct FFI calls |
| glide-ffi | Rust cdylib | Built from valkey-glide/ffi | glide-core |
| glide-core | Rust | N/A (in valkey-glide repo) | Valkey/Redis protocol |

```
Ruby (Valkey#send_command)
  → Bindings.command / Bindings.batch
    → libglide_ffi (Rust)
      → glide-core
        → Valkey / Redis OSS
```

Same FFI stack as **Go** and **Python sync**; different from Java (JNI) and Python async (PyO3 + UDS).

## Context Retrieval

When working on a feature, read these paths first:

| Topic | Read first |
|-------|------------|
| Connection / options | `lib/valkey.rb` (`#initialize`), `test/lint/connection_options.rb` |
| New command | `lib/valkey/request_type.rb`, matching `lib/valkey/commands/*.rb`, `test/lint/*` |
| Pipelining / batch | `lib/valkey.rb` (`pipelined`, `send_batch_commands`), `lib/valkey/pipeline.rb` |
| OpenTelemetry | `lib/valkey/opentelemetry.rb`, `test/valkey/test_opentelemetry.rb` |
| FFI / errors | `lib/valkey/bindings.rb`, `lib/valkey/errors.rb` |
| Cluster | `test/support/helper/cluster.rb`, `test/cluster/` |
| Upstream semantics | [valkey-glide glide-core](https://github.com/valkey-io/valkey-glide/tree/main/glide-core), peer client in `go/` or `python/glide-sync/` |

## Build and Test (quick reference)

```bash
bin/setup
bundle exec rubocop
bundle exec rake test:valkey      # needs localhost:6379
bundle exec rake test:cluster     # needs cluster 7000-7005
```

Rebuild FFI after core changes:

```bash
cd valkey-glide/ffi && cargo build --release
cp target/release/libglide_ffi.* /path/to/valkey-glide-ruby/lib/valkey/
```

## Agent docs in this repo

- [AGENTS.md](./AGENTS.md) — build/test/contribution checklist for agents
- [CONTRIBUTING.md](./CONTRIBUTING.md) — PR and DCO guidelines
- [DEVELOPER.md](./DEVELOPER.md) — full developer setup guide
- [examples/](./examples/) — runnable sample scripts
- [README.md](./README.md) — user-facing getting started

Upstream mono-repo agent context: [valkey-glide/AGENTS.md](https://github.com/valkey-io/valkey-glide/blob/main/AGENTS.md), [valkey-glide/CLAUDE.md](https://github.com/valkey-io/valkey-glide/blob/main/CLAUDE.md).
