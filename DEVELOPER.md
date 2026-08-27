# Developer Guide

How to set up local development, run the tests, and run RuboCop for the Valkey
GLIDE Ruby client (`valkey-glide-rb`). For architecture and contribution rules,
see [AGENTS.md](./AGENTS.md).

## Prerequisites

- **Ruby** 3.0+ and **Bundler**
- **git** (the repo uses the `valkey-glide` submodule for the native FFI and test tooling)
- **Rust toolchain** ([rustup](https://rustup.rs/)) and **protoc**, needed only to build the native library
- **Python 3**, used by the test suite to start servers with the submodule's `cluster_manager.py`
- A **Valkey** (or Redis OSS) server for integration tests

## Local Setup

```bash
# Clone with the submodule
git clone --recurse-submodules https://github.com/valkey-io/valkey-glide-ruby.git
cd valkey-glide-ruby
# (already cloned? initialize the submodule)
git submodule update --init --recursive

# Install gems
bin/setup

# Build the native FFI library (release mode)
rake native:build
```

Verify the client loads:

```bash
bundle exec ruby -e 'require "valkey"; puts Valkey::VERSION'
```

## Running Tests

Tests use **Minitest**, split into `rake test:unit` (`test/unit/`, no server needed),
`rake test:standalone` (`test/integration/standalone/` + `test/integration/valkey/`),
and `rake test:cluster` (`test/integration/cluster/`).

Start test servers with the submodule's `cluster_manager.py`. It's the same tool
CI uses, so ports and topology match. Only fall back to a manual `valkey-server`
or `docker run` when a scenario can't be produced with `cluster_manager.py`.

```bash
# Standalone server on :6379 (used by test:standalone)
python3 valkey-glide/utils/cluster_manager.py start -r 0 -p 6379 --prefix standalone

# Run the suites
bundle exec rake test              # unit + integration
bundle exec rake test:unit         # unit only (no server needed)
bundle exec rake test:integration  # standalone + cluster
bundle exec rake test:standalone   # standalone only
bundle exec rake test:cluster      # cluster only (nodes auto-started by the suite)

# Stop the standalone server when done
python3 valkey-glide/utils/cluster_manager.py stop --prefix standalone
```

Common environment overrides (defaults in `test/test_helper.rb`): `VALKEY_PORT`
(6379), `VALKEY_SSL_PORT` (6380), `TIMEOUT` (5.0); test database is `15`.

```bash
VALKEY_PORT=6379 TIMEOUT=10 bundle exec rake test:standalone
```

### TLS Tests (optional)

TLS tests need a TLS server plus `TLS_CERT_DIR`. Skip them with `SKIP_TLS_TESTS=true`.

```bash
python3 valkey-glide/utils/cluster_manager.py --tls start -r 0 -p 6380 --prefix tls-standalone
export TLS_CERT_DIR=$(pwd)/valkey-glide/utils/tls_crts
bundle exec rake test:standalone
python3 valkey-glide/utils/cluster_manager.py --tls stop --prefix tls-standalone
```

## RuboCop

```bash
bundle exec rubocop        # lint (must pass before committing)
bundle exec rubocop -A     # auto-correct safe offenses
```

Config: `.rubocop.yml`, `.rubocop_todo.yml`.
