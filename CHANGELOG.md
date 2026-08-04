# Changelog

## Pending

### Changes

* Ruby: Lower the glibc requirement of the prebuilt `*-unknown-linux-gnu` native libraries to **glibc 2.17** by cross-compiling with `cargo zigbuild --target <triple>.2.17`. Previously they were built with a plain `cargo build` on glibc-2.39 runners, which baked in `GLIBC_2.38`/`GLIBC_2.39` symbol requirements and made the gem fail to load on Debian 11, Ubuntu 20.04, and Amazon Linux 2 with `version 'GLIBC_2.38' not found` ([#223](https://github.com/valkey-io/valkey-glide-ruby/issues/223))
* Ruby: Add Alpine Linux (musl libc) support for x86_64 and aarch64 — runtime detection of musl libc, CI/CD pipeline for native builds, and prebuilt `libglide_ffi.so` for musl targets ([#143](https://github.com/valkey-io/valkey-glide-ruby/pull/143))
* Ruby: Add distributed tracing support — `Valkey::OpenTelemetry.set_parent_span_context_provider` (and `init(parent_span_context_provider:)`) let an app propagate its current W3C trace context into command/pipeline spans, so they become children of the app's trace instead of independent root spans, matching the Node.js client's `parentSpanContextProvider` behavior.
