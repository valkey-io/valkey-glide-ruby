# Changelog

All notable changes to this project are documented in this file.

GLIDE Ruby follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added support for `Valkey::ReadFrom::AZ_AFFINITY_ALL_NODES` to prefer all nodes in the client's availability zone before other nodes. ([#349](https://github.com/valkey-io/valkey-glide-ruby/pull/349))
- Added support for `hgetdel(key, *fields)` with Valkey 9.1 or later. ([#348](https://github.com/valkey-io/valkey-glide-ruby/pull/348))
- Added support for IAM authentication through `Valkey::IamAuthConfig`, the `iam_config:` connection option, `refresh_iam_token`, and the ElastiCache and MemoryDB service types. ([#342](https://github.com/valkey-io/valkey-glide-ruby/pull/342))
- Added support for custom OpenTelemetry resource attributes through `Valkey::OpenTelemetry.init(resource_attributes:)`, including automatic process attributes without replacing values already set in `OTEL_RESOURCE_ATTRIBUTES`. ([#325](https://github.com/valkey-io/valkey-glide-ruby/pull/325))
- Added support for setting the `CLIENT SETINFO LIB-NAME` value with the `lib_name:` and `client_info_tag:` connection options. ([#246](https://github.com/valkey-io/valkey-glide-ruby/pull/246))
- Added support for `FT.CREATE`, `FT.DROPINDEX`, `FT.INFO`, `FT.SEARCH`, and `FT.AGGREGATE` through `Valkey::Search` builders, with structured `FT.SEARCH` results. ([#295](https://github.com/valkey-io/valkey-glide-ruby/pull/295))
- Added support for inline Pub/Sub subscriptions and message reads through `subscribe`, `unsubscribe`, `get_pubsub_message`, and `try_get_pubsub_message`. ([#308](https://github.com/valkey-io/valkey-glide-ruby/pull/308))
- Added support for pattern subscriptions, nonblocking lazy subscription changes, and callback-based Pub/Sub delivery. ([#316](https://github.com/valkey-io/valkey-glide-ruby/pull/316))
- Added support for sharded Pub/Sub in cluster mode through `ssubscribe`, `sunsubscribe`, their lazy variants, and `publish(..., sharded: true)`. ([#317](https://github.com/valkey-io/valkey-glide-ruby/pull/317))
- Added support for inspecting Pub/Sub channels, subscriber counts, and connection subscription state. ([#320](https://github.com/valkey-io/valkey-glide-ruby/pull/320))
- Added support for queuing Pub/Sub commands in `pipelined` and `multi`. ([#329](https://github.com/valkey-io/valkey-glide-ruby/pull/329))
- Added support for Alpine Linux on x86_64 and aarch64. ([#143](https://github.com/valkey-io/valkey-glide-ruby/pull/143))
- Added support for propagating W3C trace context into command and pipeline spans through `Valkey::OpenTelemetry.set_parent_span_context_provider` and `parent_span_context_provider:`. ([#161](https://github.com/valkey-io/valkey-glide-ruby/pull/161))
- Added Sigstore build-provenance attestations to gems published on RubyGems.org. ([#338](https://github.com/valkey-io/valkey-glide-ruby/pull/338))

### Changed

- Prevented `client(:subcommand)` from invoking private methods, so custom `Valkey` subclasses must make any dispatched `client_*` handlers public. ([#246](https://github.com/valkey-io/valkey-glide-ruby/pull/246))
- Trimmed whitespace from string `client_az` values and rejected blank values when an availability-zone affinity strategy is selected. ([#349](https://github.com/valkey-io/valkey-glide-ruby/pull/349))
- Changed `eval`, `evalsha`, their read-only variants, and `script_load` to execute server commands, accept integer key counts, and report missing scripts instead of reloading them automatically. ([#227](https://github.com/valkey-io/valkey-glide-ruby/pull/227))
- Changed the default RESP protocol to RESP3, in line with other GLIDE clients. ([#331](https://github.com/valkey-io/valkey-glide-ruby/pull/331))

### Removed

- Removed raw-token options, `ft(:subcommand)`, unsupported `FT.*` wrappers, and the `dd:` option from the Search API; use `call` for raw Search commands. ([#295](https://github.com/valkey-io/valkey-glide-ruby/pull/295))

### Fixed

- Rejected `cluster_mode: true` without an explicit seed node instead of connecting to the standalone default. ([#344](https://github.com/valkey-io/valkey-glide-ruby/pull/344))
- Treated empty `lib_name:` and `client_info_tag:` values as unset so they no longer produce invalid library names. ([#246](https://github.com/valkey-io/valkey-glide-ruby/pull/246))
- Placed the `xpending` `idle:` filter in the correct command position and omitted it only when its value is `nil`. ([#300](https://github.com/valkey-io/valkey-glide-ruby/pull/300))
- Raised `Valkey::InheritedError` instead of terminating the process when a child process uses a client created before `fork()`. ([#302](https://github.com/valkey-io/valkey-glide-ruby/pull/302))
- Preserved successful pipeline and transaction replies when another queued command fails, added `multi(exception: false)`, distinguished queue-time aborts with `Valkey::ExecAbortError`, and retained float and error values in transaction results. ([#299](https://github.com/valkey-io/valkey-glide-ruby/pull/299))
- Restored `blpop`, `brpop`, `blmove`, `rpoplpush`, and `brpoplpush`, with the deprecated pop-push methods delegated to `lmove` and `blmove`. ([#220](https://github.com/valkey-io/valkey-glide-ruby/pull/220))
- Released the Ruby global VM lock while creating a client so other Ruby threads can continue running during connection setup. ([#316](https://github.com/valkey-io/valkey-glide-ruby/pull/316))
- Sized FFI argument-length buffers for the platform's `unsigned long` width to prevent memory corruption on platforms where it is four bytes. ([#338](https://github.com/valkey-io/valkey-glide-ruby/pull/338))
- Built Linux release binaries against glibc 2.17 for compatibility with supported Linux distributions. ([#232](https://github.com/valkey-io/valkey-glide-ruby/pull/232))

## [1.0.0] - 2026-08-12

### Added

- Published the first general availability release.

[Unreleased]: https://github.com/valkey-io/valkey-glide-ruby/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/valkey-io/valkey-glide-ruby/releases/tag/v1.0.0
