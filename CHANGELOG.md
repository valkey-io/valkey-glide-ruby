# Changelog

## 1.1.0 (Pending)

### Breaking Changes

* feat(ruby): `client(:subcommand)` dispatches with `public_send`, so subclasses relying on private `client_*` helpers must make them public; a private subcommand now raises `NoMethodError` instead of being silently dispatched (landed in `a11baf7`, which removed the client-side-caching commands from the public interface) ([#246](https://github.com/valkey-io/valkey-glide-ruby/pull/246))

### Fixes

* fix(ruby): treat an empty `lib_name` or `client_info_tag` as "not configured". Previously `lib_name: ""` plus a tag composed `(tag)` instead of `GlideRuby(tag)`, which glide-core rejects, surfacing as `Valkey::CannotConnectError` at client creation ([#246](https://github.com/valkey-io/valkey-glide-ruby/pull/246))

* Ruby: Fix `xpending`'s `idle:` option, which was emitted after `start`/`end`/`count` instead of before them. The Valkey `XPENDING` grammar is `XPENDING key group [IDLE ms] start end count [consumer]`, so the trailing `IDLE <ms>` was parsed by the server as the optional `consumer` argument, causing `xpending(key, group, start, end, count, idle: ms)` to silently return an empty result set instead of the idle-filtered entries. Also, `idle: false` was previously indistinguishable from `idle: nil` (both are falsy in Ruby) and silently dropped the filter instead of forwarding it to the server; `idle:` is now only omitted when explicitly `nil` ([#270](https://github.com/valkey-io/valkey-glide-ruby/issues/270), [#241](https://github.com/valkey-io/valkey-glide-ruby/issues/241)).
* fix(ruby): raise `Valkey::InheritedError` instead of crashing the process when a client created before `fork()` is used in the child ([#255](https://github.com/valkey-io/valkey-glide-ruby/issues/255))
* Ruby: Fix `blpop`, `brpop`, `blmove`, `rpoplpush` and `brpoplpush`, all of which were non-functional. `blpop`/`brpop` called a non-existent `send_blocking_command` helper, `blmove` leaked the command name into argv, and `rpoplpush`/`brpoplpush` dispatched `RequestType::RPOPLPUSH`/`BRPOPLPUSH`, for which glide-core has no command mapping. Since Valkey defines `RPOPLPUSH src dst` as exactly `LMOVE src dst RIGHT LEFT` (and `BRPOPLPUSH src dst timeout` as `BLMOVE src dst RIGHT LEFT timeout`), `rpoplpush`/`brpoplpush` are now fixed-argument facades over `lmove`/`blmove`. Both remain deprecated as of Redis 6.2; prefer `lmove`/`blmove` in new code. The unusable `RequestType::RPOPLPUSH`/`BRPOPLPUSH` constants were removed.

### Changes

* feat(ruby): add `lib_name` and `client_info_tag` connection options controlling the `CLIENT SETINFO LIB-NAME` value; `client_info_tag` appends a parenthesized tag to the resolved name (`GlideRuby(my-framework:1.0)`) and is preferred for framework attribution, while `lib_name` overrides the name outright and the two combine as `<lib_name>(<tag>)`. Invalid types raise `ArgumentError` at construction, which is deliberately outside the `Valkey` error hierarchy and so is not caught by `rescue Valkey::BaseError`; invalid names fail client creation with `Valkey::CannotConnectError`. See the `lib_name` row in README's Connection Options ([#246](https://github.com/valkey-io/valkey-glide-ruby/pull/246))

* Ruby: fixed cd workflow to correctly build the ffi with **glibc 2.17** ([#223](https://github.com/valkey-io/valkey-glide-ruby/issues/223))
* Ruby: scripting commands now dispatch real `EVAL` / `EVALSHA` / `SCRIPT LOAD` to the server instead of a client-side script container ([#213](https://github.com/valkey-io/valkey-glide-ruby/issues/213)). Three behavior changes:
  * `eval` / `evalsha` (and the `_ro` variants) now accept the standard integer key-count form used by `valkey-cli` and the Valkey docs — `eval(script, 1, "mykey", "myarg")`. It previously made the count `KEYS[1]`, shifted the real key into `ARGV[1]`, and dropped the remaining arguments without raising.
  * `script_load` now really sends `SCRIPT LOAD`, so the returned SHA1 is known to the server and usable by `evalsha` from any other client or process. `script_exists` previously reported `false` for a just-loaded script.
  * `evalsha` on a flushed or never-loaded SHA now raises `Valkey::CommandError` (NOSCRIPT) instead of silently re-uploading the script and succeeding, so `script_flush` is no longer quietly undone. Callers relying on the old auto-reload must load the script again after a flush, or use `eval`.
* Ruby: Add Alpine Linux (musl libc) support for x86_64 and aarch64 — runtime detection of musl libc, CI/CD pipeline for native builds, and prebuilt `libglide_ffi.so` for musl targets ([#143](https://github.com/valkey-io/valkey-glide-ruby/pull/143))
* Ruby: Add distributed tracing support — `Valkey::OpenTelemetry.set_parent_span_context_provider` (and `init(parent_span_context_provider:)`) let an app propagate its current W3C trace context into command/pipeline spans, so they become children of the app's trace instead of independent root spans, matching the Node.js client's `parentSpanContextProvider` behavior.

## 1.0.0

GA Release
