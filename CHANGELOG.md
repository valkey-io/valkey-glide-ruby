# Changelog

## Pending

### Fixes

* Ruby: Fix `blpop`, `brpop`, `blmove`, `rpoplpush` and `brpoplpush`, all of which were non-functional. `blpop`/`brpop` called a non-existent `send_blocking_command` helper, `blmove` leaked the command name into argv, and `rpoplpush`/`brpoplpush` dispatched `RequestType::RPOPLPUSH`/`BRPOPLPUSH`, for which glide-core has no command mapping. Since Valkey defines `RPOPLPUSH src dst` as exactly `LMOVE src dst RIGHT LEFT` (and `BRPOPLPUSH src dst timeout` as `BLMOVE src dst RIGHT LEFT timeout`), `rpoplpush`/`brpoplpush` are now fixed-argument facades over `lmove`/`blmove`. Both remain deprecated as of Redis 6.2; prefer `lmove`/`blmove` in new code. The unusable `RequestType::RPOPLPUSH`/`BRPOPLPUSH` constants were removed.

### Changes

* Ruby: fixed cd workflow to correctly build the ffi with **glibc 2.17** ([#223](https://github.com/valkey-io/valkey-glide-ruby/issues/223))
* Ruby: Add Alpine Linux (musl libc) support for x86_64 and aarch64 — runtime detection of musl libc, CI/CD pipeline for native builds, and prebuilt `libglide_ffi.so` for musl targets ([#143](https://github.com/valkey-io/valkey-glide-ruby/pull/143))
* Ruby: Add distributed tracing support — `Valkey::OpenTelemetry.set_parent_span_context_provider` (and `init(parent_span_context_provider:)`) let an app propagate its current W3C trace context into command/pipeline spans, so they become children of the app's trace instead of independent root spans, matching the Node.js client's `parentSpanContextProvider` behavior.
