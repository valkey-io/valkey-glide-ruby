# Testing Gaps Analysis

This document identifies testing gaps in the Ruby GLIDE client compared to other language implementations (Python, Java, Node.js, Go, C#, PHP).

## Current Test Coverage

The Ruby client has ~742 test methods across ~10,200 lines of test code, covering:

- ✅ Core command families (strings, hashes, lists, sets, sorted sets, streams, etc.)
- ✅ Pipelining
- ✅ Transactions (MULTI/EXEC)
- ✅ Cluster commands
- ✅ OpenTelemetry integration
- ✅ Statistics
- ✅ SSL/TLS connections
- ✅ redis-rb compatibility (lint tests)
- ✅ PubSub (basic - publish, pubsub_channels, pubsub_numsub, etc.)
- ✅ Authentication (URL parsing, ACL commands)
- ✅ Reconnection strategy configuration

---

## Missing Tests (Functionality Exists)

These features are implemented in the Ruby client but lack comprehensive test coverage.

### 1. Cluster Management Infrastructure

**Status**: Test infrastructure missing

Ruby tests expect a pre-existing cluster on ports 7000-7005 (via Docker). Other languages can programmatically create and manage clusters using `cluster_manager.py`.

| Language | Approach | Programmatic Cluster Creation |
|----------|----------|-------------------------------|
| Python | `ValkeyCluster` class wraps `cluster_manager.py` | ✅ Yes |
| Java | Uses shared `cluster_manager.py` utility | ✅ Yes |
| Node.js | Uses shared `cluster_manager.py` utility | ✅ Yes |
| Go | Uses shared `cluster_manager.py` utility | ✅ Yes |
| C# | `ServerManager.cs` wraps `cluster_manager.py` | ✅ Yes |
| PHP | Shell scripts + `cluster_manager.py` for TLS/auth | ✅ Partial |
| **Ruby** | Expects pre-existing Docker cluster | ❌ No |

**Impact**: Cannot test:
- Different shard/replica configurations
- Cluster creation and initialization
- Cluster failover scenarios
- Dynamic cluster topology changes
- TLS clusters
- Auth-enabled clusters

**Recommendation**: Create a `ClusterManager` class that wraps `cluster_manager.py` from the valkey-glide submodule, similar to C#'s `ServerManager.cs`.

### 2. Reconnection/Failover Behavior

**Status**: Functionality exists, tests are minimal

The client supports `reconnect_attempts`, `reconnect_delay`, and `reconnect_delay_max` options, and the FFI layer handles reconnection. However, tests only verify configuration parsing, not actual reconnection behavior.

**What exists in Ruby**:
- `connection_retry_strategy` passed to FFI layer
- Parameter validation tests in `uri_connection_test.rb`

**What's missing**:
- Tests that verify reconnection after server disconnect
- Tests for failover to replicas
- Tests for behavior during network partitions

**What other clients have**:
- **Python**: `test_lazy_connection.py` - tests connection behavior and lazy initialization
- **C#**: Error handling tests, connection timeout tests
- **PHP**: Connection tests with various failure scenarios

### 3. Client-Side Caching Commands

**Status**: Commands exist, tests are skipped

The `client_caching` command is implemented, but tests are skipped with notes about backend limitations.

**What exists in Ruby**:
- `client_caching(mode)` method
- `client_tracking` method
- Tests exist but are skipped

**What's missing**:
- Working tests for CLIENT CACHING
- Tests for cache invalidation
- Tests for OPTIN/OPTOUT modes

**What other clients have**:
- **C#**: `ClientSideCacheTests.cs` - comprehensive tests for cache configuration, metrics, hit/miss rates, TTL expiration, eviction policies (LRU/LFU), multi-key operations
- **PHP**: `ClientSideCacheTest.php` - tests for cache config, metrics, eviction, TTL
- **Python**: `test_client_side_cache.py` - async tests for caching behavior

### 4. Authentication (Comprehensive)

**Status**: Basic functionality exists, limited testing

Authentication via URL and options works, but tests only verify URL parsing doesn't crash. No tests against an auth-enabled server.

**What exists in Ruby**:
- `username` and `password` options
- URL parsing with credentials
- ACL commands (whoami, genpass, etc.)

**What's missing**:
- Tests against auth-enabled Valkey server
- Tests for auth during reconnection
- Tests for ACL-based access control
- Tests for password rotation

**What other clients have**:
- **Python**: `test_auth.py` - authentication tests
- **C#**: `IamAuthTests.cs` - IAM authentication tests
- **PHP**: `IamAuthTest.php`, `UpdateConnectionPasswordTest.php` - auth and password update tests

### 5. Request Routing (Cluster)

**Status**: Functionality exists in FFI, limited testing

Cluster mode works, but tests don't verify routing behavior for edge cases.

**What exists in Ruby**:
- `cluster_mode: true` option
- Cluster commands (CLUSTER SLOTS, CLUSTER NODES, etc.)
- Basic cluster command tests

**What's missing**:
- Tests for MOVED/ASK redirections
- Tests for slot migration handling
- Tests for multi-key commands across slots
- Tests for read-from-replica routing

**What other clients have**:
- **Python**: `test_read_from_strategy.py` - read replica routing tests
- **C#**: `ConnectionMultiplexerReadFromMappingTests.cs`, `AzAffinityTests.cs` - routing and affinity tests

### 6. CI Test Matrix Coverage

**Status**: Limited platform and version coverage

The CI only tests a subset of claimed supported platforms and Ruby versions.

**What's tested in CI**:
- **Platforms**: Ubuntu (x86_64 only for tests, aarch64 for builds)
- **Ruby versions**: 3.0, 3.1, 3.2, 3.3, 3.4
- **Valkey versions**: 7.2.10, 8, 8.1

**What's NOT tested but claimed/implied**:
- Ruby 2.6, 2.7 (gemspec says >= 2.6.0)
- JRuby
- macOS (x86_64, aarch64)
- Amazon Linux
- Redis OSS 6.2, 7.0, 7.2

**What other clients have**:
- **Python**: Tests across multiple Python versions, OS matrix
- **C#**: Tests on Windows, Linux, macOS
- **Java**: Tests across JDK versions and platforms

### 7. Library Name (CLIENT SETINFO lib-name)

**Status**: ✅ Fixed (PR pending)

The Ruby client now sets `GLIDE_NAME=GlideRuby` during native library build, which is sent via `CLIENT SETINFO lib-name` during connection handshake.

**What other clients have**:
- **C#**: Sets `LibraryName => "GlideCSharp"` automatically
- **Go**: Sets `GLIDE_NAME=GlideGo` during build
- **Python**: Sets `GLIDE_NAME=GlidePy` or `GlidePySync` during build

---

## Missing Functionality

These features don't exist in the Ruby client and would need to be implemented.

### 1. Compression

**Status**: Not implemented

No compression configuration options exist in the Ruby client. The `statistics` method returns compression metrics, but these are from the FFI layer and there's no way to enable or configure compression from Ruby.

**What other clients have**:
- **C#**: `CompressionTests.cs` - tests for Zstd and LZ4 compression, configurable via `WithCompression(CompressionConfig.Zstd())`, threshold settings
- **Python**: `test_compression.py` - compression configuration and behavior tests
- **Java**: Compression support with algorithm selection

### 2. Inflight Requests Limit

**Status**: Not exposed in Ruby API

GLIDE uses multiplexed connections (one connection per node) with concurrent request handling, controlled by `inflight_requests_limit`. This is not exposed in the Ruby client.

**What other clients have**:
- **Python**: `inflight_requests_limit` parameter in client configuration
- **Node.js**: `inflightRequestsLimit` option
- **FFI layer**: Supports `inflight_requests_limit` in JSON options (default: 1000)

**Note**: GLIDE does NOT use traditional connection pooling. Instead, it multiplexes many concurrent requests over a single connection per node, which is more efficient.

### 3. DNS-Based Discovery

**Status**: Not implemented

No support for DNS-based cluster discovery or SRV records.

**What other clients have**:
- **C#**: `DnsTests.cs` - tests for hostname resolution, TLS with hostname verification, invalid hostname handling
- **PHP**: `ValkeyGlideDnsTest.php`, `ValkeyGlideClusterDnsTest.php` - DNS discovery tests

### 4. PubSub Subscriptions (Blocking)

**Status**: Partially implemented

The client has `publish` and `pubsub_*` query commands, but blocking subscription commands (`SUBSCRIBE`, `PSUBSCRIBE`) require a different architecture.

**What exists in Ruby**:
- `publish`, `spublish`
- `pubsub_channels`, `pubsub_numsub`, `pubsub_numpat`
- `pubsub_shardchannels`, `pubsub_shardnumsub`
- PubSub callback mechanism in FFI

**What's missing**:
- Blocking `subscribe`/`psubscribe` commands
- Message handler callbacks
- Subscription persistence across reconnects
- Pattern subscription tests

**What other clients have**:
- **C#**: `PubSubBasicTests.cs`, `PubSubCallbackTests.cs`, `PubSubSubscribeTests.cs`, `PubSubEdgeCases.cs` - comprehensive subscription tests with callbacks, multiple subscribers, pattern matching
- **PHP**: `ValkeyGlidePubSubTest.php`, `ValkeyGlideClusterPubSubTest.php` - uses separate subscriber processes
- **Python**: `test_pubsub.py` - async pubsub tests

---

## Priority Recommendations

### High Priority
1. **Cluster Management Infrastructure** - Enables testing many other scenarios
2. **Reconnection/Failover Behavior** - Critical for production reliability
3. **Authentication (Comprehensive)** - Security-critical functionality
4. **CI Test Matrix Coverage** - Validate claimed platform/version support

### Medium Priority
5. **Request Routing (Cluster)** - Important for cluster deployments
6. **PubSub Subscriptions** - Common use case, partially blocked

### Lower Priority
7. **Compression** - Nice-to-have optimization, needs FFI support
8. **Client-Side Caching** - Depends on backend support
9. **Inflight Requests Limit** - Expose existing FFI parameter
10. **DNS-Based Discovery** - Specialized deployment scenario

---

## Next Steps

1. **Create `ClusterManager` utility** - Wrap `cluster_manager.py` for programmatic cluster creation
2. **Add auth-enabled test infrastructure** - Create clusters with authentication for testing
3. **Implement reconnection behavior tests** - Test actual disconnect/reconnect scenarios
4. **Investigate PubSub subscription architecture** - Determine if blocking subscriptions are feasible

---

## References

- [Python tests](https://github.com/valkey-io/valkey-glide/tree/main/python/tests)
- [Java tests](https://github.com/valkey-io/valkey-glide/tree/main/java/integTest)
- [Node.js tests](https://github.com/valkey-io/valkey-glide/tree/main/node/tests)
- [Go tests](https://github.com/valkey-io/valkey-glide/tree/main/go/integTest)
- [C# tests](https://github.com/valkey-io/valkey-glide-csharp/tree/main/tests)
- [PHP tests](https://github.com/valkey-io/valkey-glide-php/tree/main/tests)
- [cluster_manager.py utility](https://github.com/valkey-io/valkey-glide/blob/main/utils/cluster_manager.py)
