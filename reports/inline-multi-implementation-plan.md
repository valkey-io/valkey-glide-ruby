# Implementation plan: back inline `multi`/`exec`/`discard` with a buffered atomic batch

Plan of record for [#314](https://github.com/valkey-io/valkey-glide-ruby/issues/314). Baseline `origin/main` = `1e61c7f`, submodule `f1ce42285`. Related: [#272](https://github.com/valkey-io/valkey-glide-ruby/issues/272) (unify the two code paths), [#209](https://github.com/valkey-io/valkey-glide-ruby/issues/209) (per-command error coercion), [#263](https://github.com/valkey-io/valkey-glide-ruby/issues/263) (asks for the opposite resolution, see Decisions), [#261](https://github.com/valkey-io/valkey-glide-ruby/issues/261) / [#165](https://github.com/valkey-io/valkey-glide-ruby/issues/165) (scoped connections, out of scope here).

## Goal

Stop sending `MULTI` eagerly. Record the inline form's commands into the existing `Pipeline` and flush them as one atomic batch when `exec` is called, which is the path the block form already uses. This removes the open server-side transaction that spans multiple round trips, and with it the cluster misrouting, the cross-thread leakage, and the reconnect data loss described in #314.

Keeping the inline form is a requirement. Consumers are on redis-rb 3.x and depend on it.

## Non-goals

- Removing or deprecating the inline form.
- `WATCH` on a genuinely dedicated connection. `watch` then read then `multi` then `exec` keeps working under this plan, but a client shared across threads and a reconnect mid-flight remain unsafe for `WATCH`, exactly as they are for the block form today. That needs the scope FFI (#261 / #165).
- Batch-level routing (#137) and batch retry strategy (#136).

## Sequencing

Phase 0 fixes bugs that exist on `main` today and are independent of this work. They must land first, because Phase 2 routes the inline form onto the code they affect. Phase 1 is a small guard shippable immediately and independently. Phase 2 is the refactor. Phases 3 to 5 land with it.

---

## Phase 0: prerequisites, shippable independently

### P0.1 Nil-guard the batch reply conversion

`lib/valkey.rb:695-697`

```ruby
blocks.each_with_index do |block, i|
  results[i] = block.call(results[i]) if block && !results[i].is_a?(CommandError)
end
```

`results` is `nil` when glide-core returns `Value::Nil` for a `WATCH`-aborted `EXEC`, and the condition evaluates `results[i]` before the `block &&` guard can help. Reproduced on `main`:

```ruby
c.watch("k"); other.set("k", "changed")
c.multi { |m| m.zscore("z", "m") }
# => NoMethodError: undefined method '[]' for nil
```

It only fires when a queued command carries a conversion block, which is why the existing tests miss it. They queue only `set`, which passes none. Affects `zscore`, `hgetall`, `incrbyfloat`, `config_get`, `xrange`, and every other command that passes a block.

`Pipeline#resolve_futures!` already guards `results.nil?` at `lib/valkey/pipeline.rb:42`. This path must too.

Acceptance: `c.multi { |m| m.zscore(...) }` after an aborted watch returns `nil`. Regression test queues a block-carrying command, not `set`.

### P0.2 Copy args when queueing into a Pipeline

`lib/valkey/pipeline.rb:24` stores the args array by reference where `send_command` dups it (`lib/valkey.rb:537`). A caller mutating the array after queueing changes what is sent.

```ruby
@commands << [command_type, command_args.dup, block]
```

Acceptance: mutating an args array after queueing does not change the command sent. Also fixes `pipelined`.

### P0.3 Do not run conversion blocks over the `QUEUED` sentinel on the batch path

`send_batch_commands` applies each command's block unconditionally, so `Utils::Boolify.call("QUEUED")` returns `true`. Reproduced on `main`:

```ruby
c.pipelined { |p| p.multi; p.hsetnx("h", "f", "1"); p.exec }
# => ["OK", "QUEUED", true, [1, 1]]
#                     ^^^^ should be "QUEUED"
```

`convert_response` already guards this at `lib/valkey.rb:853` (`if block_given? && response != "QUEUED"`). Mirror it.

Acceptance: the literal sentinel survives unconverted. Affects `hexists`, `hsetnx`, `sadd`, `srem`, `setnx`, `zadd`.

---

## Phase 1: reject the inline form in cluster mode, shippable immediately

Raise from `start_multi` when `cluster_mode?`. Today `multi` reports success, sets the transaction state, and then loses atomicity quietly, leaving abandoned `MULTI`s on nodes.

Nothing is being validated there. `test/lint/transaction_commands.rb` carries 42 `skip("... not supported in cluster mode")` calls, so nothing regresses. #121 is the precedent for a per-mode client-side guard.

This is an interim measure. Phase 2 makes cluster work and this guard comes back out.

Acceptance: inline `multi` raises a clear error in cluster mode naming the block form as the alternative. Block form unaffected.

---

## Phase 2: the refactor

### P2.1 State

`lib/valkey.rb`

```ruby
QUEUED = "QUEUED"

def initialize(options = {})
  # ...
  # One fiber-local slot per client, so two clients in one fiber stay independent.
  @transaction_slot = :"valkey_transaction_#{object_id}"
end

private

def current_transaction
  Thread.current[@transaction_slot]
end

def begin_transaction
  Thread.current[@transaction_slot] ||= Pipeline.new
end

def end_transaction
  Thread.current[@transaction_slot] = nil
end
```

Fiber-local rather than an instance variable, because one `Valkey` instance is meant to be shared across threads. An instance-level buffer would capture another thread's command exactly as the server does today, relocating the bug rather than fixing it. `Thread#[]` is fiber-local, which is finer-grained than thread-local: every thread has its own root fiber, so this gives thread isolation and additionally isolates fibers within a thread, which matters under Falcon or the `async` gem. Available since Ruby 1.9, so it clears the 3.0 floor. `Fiber#storage` would be cleaner but is 3.2+.

`||=` preserves today's behavior that a second `multi` is a client-side no-op, and cannot discard an in-progress buffer.

Deletes `@in_multi` and `@queued_commands`.

### P2.2 Dispatch

`lib/valkey.rb`, one diversion point, which is why no command method changes.

```ruby
# Commands that carry per-connection server state cannot be batched.
UNBUFFERABLE = [RequestType::WATCH, RequestType::UNWATCH].freeze

def send_command(command_type, command_args = [], route: nil, &block)
  conn = connection!

  transaction = current_transaction
  if transaction && !UNBUFFERABLE.include?(command_type)
    raise ArgumentError, "route: cannot be applied to a command queued in a transaction" if route
    transaction.send_command(command_type, command_args, &block)
    return QUEUED
  end

  # ...existing FFI body, unchanged...
end
```

`connection!` stays first so a closed or forked client fails fast rather than silently buffering.

Both guards are load-bearing. Buffering `WATCH` or `UNWATCH` flushes them inside the `MULTI`, where the server rejects them and kills the whole transaction. Today only that one command fails. And `route:` must raise rather than vanish, matching `Pipeline#call`, which already raises `ArgumentError` for it (`lib/valkey/pipeline.rb:176-182`).

Deletes the queued-command tracking stanza at `lib/valkey.rb:530-539`.

### P2.3 Transaction methods

`lib/valkey/commands/transaction_commands.rb`

```ruby
def multi(exception: true)
  if block_given?
    # ...existing block form, unchanged...
  else
    begin_transaction
    self
  end
end

def exec
  transaction = current_transaction
  return nil unless transaction

  end_transaction
  return [] if transaction.commands.empty?

  results = send_batch_commands(transaction.commands, exception: false, is_atomic: true)
  transaction.resolve_futures!(results)
  results
end

def discard
  return nil unless current_transaction

  end_transaction
  "OK"
end
```

`end_transaction` runs before the flush so a raise from `send_batch_commands` cannot leave the client buffering. `discard` needs no round trip, since nothing was sent.

Add a size assertion before `resolve_futures!`. It indexes blindly (`pipeline.rb:41-45`) where the deleted `reconvert_queued_replies` had a `result.size == queued_commands.size` guard.

### P2.4 Fix `watch`'s block-form cleanup

`lib/valkey/commands/transaction_commands.rb:124-129` rescues `StandardError` and calls `unwatch` without discarding. A raise inside `watch { multi; set; raise }` leaves the fiber holding a buffer that the next `exec` commits, which is the write the author abandoned. `discard` before `unwatch`.

### P2.5 Give `Pipeline` its own transaction methods

`Pipeline` includes `Commands` but is not a `Valkey` subclass, so the P2.1 helpers are out of reach and `pipeline.multi` / `#exec` / `#discard` raise `NameError`. `test_multi_in_pipeline` currently passes and would start failing.

Decide per Decisions D1 whether these append literal request types as they do now, or raise deliberately. Either way they need an explicit implementation on `Pipeline`. Also remove the now-dead `@in_multi = false` and its comment at `lib/valkey/pipeline.rb:14-16`.

### P2.6 Update the FT guard

`lib/valkey/commands/vector_search_commands.rb:314-317` reads `@in_multi`. Switch to `current_transaction`. Without this the guard silently stops firing and `ft_search` inside a transaction fails as `TypeError: FT.SEARCH reply had a non-integer count: "Q"`.

The two unit tests set `@in_multi` on a `FakeClient` (`test/unit/commands/search_query_test.rb:370`, `search_aggregate_test.rb:270`), so they pass whether or not the guard works. Rewrite them against the new mechanism.

### P2.7 Delete the binding-side coercion table

Remove `reconvert_queued_replies` and `BOOLEAN_REQUEST_TYPES`. glide-core's `convert_pipeline_values_to_expected_types` coerces per queued command, including the Map, Double, and Set shapes the hand-rolled boolean table never covered.

Note for expectation setting: running 56 command shapes three ways found 53 identical, so the table was doing its job for ordinary transactions. The win is the edge cases and no longer having to track glide-core's `value_conversion.rs` by hand. Confirmed shape changes, all of them fixes and all of them breaking for existing inline callers: `smismember` `[1, 0]` to `[true, false]`, `script(:exists)` `1` to `true`, `zrandmember(k, n, with_scores: true)` from raising `ArgumentError` to correct pairs, plus `geopos`, `xread`, `lmpop`, `xinfo`, `function_stats`.

### P2.8 Decide the fate of `Valkey::ExecAbortError`

It is raised in exactly one place, the `EXECABORT` branch of the single-command `convert_response` (`lib/valkey.rb:771`), which this change removes from the inline path. The batch path raises plain `Valkey::CommandError` instead. Verified both.

The `CHANGELOG.md` 1.1.0 entry advertising `ExecAbortError` "so callers can tell the two apart" is therefore already inaccurate today. Either remap `EXECABORT` in `send_batch_commands` so the class survives, or delete it and correct the CHANGELOG. Do not leave a public error class orphaned.

### P2.9 Remove the Phase 1 cluster guard

Single-slot inline transactions work after P2.2. Cross-slot raises `CROSSSLOT` before dispatch instead of half-committing.

---

## Phase 3: decisions required

These change what gets written. Settle them before or during Phase 2, not after.

**D1. `pipelined` containing an inline `multi`.** Today `Pipeline` includes `TransactionCommands`, so `p.multi` appends a literal `RequestType::MULTI` and `send_batch_commands` takes a sequential fallback (`lib/valkey.rb:592-606`). Options: keep that behavior, or raise. Related: the `AGENTS.md:265` guardrail says not to remove the fallback "without fixing FFI batch stability", but pushing literal `MULTI`/`SET`/`SADD`/`EXEC` straight through `Bindings.batch` was tried during review and produced correct results with no crash. The guardrail looks stale. Verify independently before acting on it, then update `AGENTS.md` and the CHANGELOG.

**D2. `pipelined` called while an inline transaction is open.** Currently unguarded and it fabricates values. Raise, or nest into the buffer.

**D3. `exec(exception:)`.** The block form defaults to `exception: true` and raises on a per-command error. This plan hardcodes `exception: false` for the inline form to preserve today's return-the-error-in-the-array contract. Two spellings of one API with opposite error contracts is hard to defend. Either add the kwarg or document why not.

**D4. Abandoned buffers.** A pooled worker thread's root fiber outlives the request, so a forgotten `multi` leaves a buffer that the next request on that thread inherits. It swallows that request's commands, returning `"QUEUED"` for reads and deferring writes. This is the same observable failure as today, scoped to one fiber instead of the connection, so it is relocated rather than fixed. Add a defensive clear, or document it as a known sharp edge. Recommendation: defensive clear.

**D5. #263.** It asks for the opposite resolution, that `multi` with no block should raise `LocalJumpError`. Close it as won't-fix with a pointer to #314, or a reviewer will judge this work against the wrong acceptance criteria.

---

## Phase 4: tests

Existing tests to rewrite:

| Test | Why |
|---|---|
| `test_exec_raises_exec_abort_error_after_a_queue_time_error` (`transaction_commands.rb:163`) | queue-time errors move to `exec` time and the error class changes |
| `test_exec_with_error` (`:148`) | only asserts `Array`, which is why #209 went unnoticed. Assert the full shape |
| `test_transaction_isolation` (`:409`) | still passes, but its 6-line comment about the connection being unable to read pre-transaction values becomes wrong |
| `test_multi_in_pipeline` (`:102`) | depends on D1 |
| `search_query_test.rb:370`, `search_aggregate_test.rb:270` | see P2.6 |
| `test/unit/fork_safety_test.rb:42-43` | sets the deleted ivars |

New tests, none of which exist today:

- abandoned buffer inherited across a pooled thread's requests
- `watch` / `unwatch` issued inside an open inline transaction
- `pipelined` inside an open inline transaction
- `exec` raising on cross-slot in cluster mode
- `exec` array shape when one queued command fails at runtime
- two clients used in one fiber
- one client used from two fibers
- a `Fiber` or `Enumerator` opened inside a transaction, which bypasses the buffer and splits atomicity

Gates per `AGENTS.md`: `bundle exec rubocop`, `rake test:unit`, `rake test:standalone`, `rake test:cluster`.

---

## Phase 5: docs and CHANGELOG

`lib/valkey/commands/transaction_commands.rb:45-55` documents the inline form as "each queued command is its own round trip" and describes leaving the transaction open until `exec`. Every sentence inverts. `:149-151` needs a documented raise path. `:244-254` claims nested `MULTI` is "effectively ignored by the client" as if matching other clients, but redis-rb 3.3.5 and 4.8.1 both raise. Fix while in there.

`README.md` has no transaction documentation at all. Grepping for multi, transaction, watch, discard, or pipeline returns nothing, and `examples/` has none either. Shipping a behavior change to the form consumers depend on with zero prose documentation is the migration risk. Add a Transactions section covering both forms, what `exec` returns and raises, and the shared-client constraint.

CHANGELOG goes under `## 1.1.0 (Pending)` then `### Breaking Changes`, not Fixes. It must state: `exec` can now raise where it returned an array containing the error; queue-time errors no longer raise at queue time; `ExecAbortError` is remapped or removed; cross-slot inline transactions raise instead of half-committing; `multi` in one thread with `exec` in another no longer works; `pipelined` containing a literal `multi` changes per D1; the inline form now costs one round trip instead of N+2; per-command OpenTelemetry spans inside an inline transaction collapse to a single batch span.

The 1.1.0 entry at `CHANGELOG.md:15` documents the machinery this change deletes. Amend or supersede it rather than leaving it to contradict the new entry.

---

## Phase 6: cluster test debt

The 42 `skip` calls in `test/lint/transaction_commands.rb` are not uniform:

- roughly 14 newly pass with the inline form working
- roughly 20 were never justified. They are block-form tests that work in cluster today, verified
- roughly 8 need keys rewritten with a hash tag, because cross-slot now raises. Among them `test_multi_with_boolean_reply_commands` (foo 12182 / someset 4189), `test_multi_with_setnx` (foo 12182 / bar 5061), `test_exec_float_coercion_matches_direct_call` (counter 6680 / Sicily 10713), `test_complex_transaction_scenario` (account:1 10997 / account:2 6806)
- `test_transaction_isolation` needs a cluster-mode client fix. It calls `_new_client(db: 15)` and cluster has no DB 15

---

## Risk

**Loud failures** are fine. A mis-scoped buffer raises from `exec` on cross-slot or on a buffered `WATCH`, and the consumer sees it immediately.

**The silent failure is the one to test for.** A buffer leaking across a pooled thread's requests returns `"QUEUED"` where a value was expected and drops the write. A consumer calling `r.set(k, v)` and ignoring the return sees nothing until data is missing. This is D4, and it is why the abandoned-buffer test is not optional.

**Rollout:** one minor bump, no opt-in flag. A flag would mean three code paths where having two is already the problem this fixes, and every bug report would start with which mode you were in.

## Verification snapshot

Measured on a prototype of Phase 2 against a live standalone and a 3-primary cluster:

- cluster single-slot inline transactions: 2 of 30 correct before, 30 of 30 after
- cluster cross-slot: silently half-committed before, raises with nothing committed after
- cross-thread leakage: reproduced 50 of 50 before, gone after
- `exec` with a mid-transaction runtime error: `[CommandError]` before with committed replies discarded, `["OK", CommandError, "1"]` after, which matches redis-rb 3.x
- round trips: N+2 before, 1 after
- `WATCH` then read then `multi` then `exec`: works before and after, in standalone and in cluster with a hash tag
