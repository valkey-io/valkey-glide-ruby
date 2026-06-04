# Implementation Plan: Cluster Manager Alignment

## Overview

This implementation plan converts the Ruby client's cluster testing infrastructure from Docker-based (`grokzen/redis-cluster`) to the shared `cluster_manager.py` script used by other GLIDE clients (Python, Java, Go). The plan creates a Ruby wrapper class, updates test helpers, modifies CI workflows, and includes property-based tests to validate correctness properties.

## Tasks

- [x] 1. Set up project foundation and dependencies
  - [x] 1.1 Add rantly gem for property-based testing to Gemfile
    - Add `gem 'rantly'` to the development dependencies in Gemfile
    - Run `bundle install` to update Gemfile.lock
    - _Requirements: Testing Strategy prerequisites_

- [x] 2. Implement Valkey::TestCluster class
  - [x] 2.1 Create lib/valkey/test_cluster.rb with core structure
    - Create new file with module/class definition
    - Define attr_readers: `addresses`, `cluster_folder`, `tls_cert_path`, `tls_key_path`, `tls_ca_cert_path`
    - Define custom error classes: `ScriptNotFoundError`, `PythonNotFoundError`, `ClusterStartError`, `OutputParseError`
    - Implement `script_path` private method to resolve path to `valkey-glide/utils/cluster_manager.py`
    - _Requirements: 1.1, 7.1, 7.2_

  - [x] 2.2 Implement script path resolution and validation
    - Implement logic to find `cluster_manager.py` relative to project root
    - Raise `ScriptNotFoundError` with informative message if script not found
    - Check for Python 3 availability, raise `PythonNotFoundError` if missing
    - Handle submodule not initialized scenario with helpful error message
    - _Requirements: 7.1, 7.2_

  - [x] 2.3 Implement initialize method with parameter handling
    - Accept parameters: `cluster_mode`, `tls`, `shard_count`, `replica_count`, `load_module`, `addresses`
    - Set defaults: `cluster_mode: false`, `tls: false`, `shard_count: 3`, `replica_count: 1`
    - When `addresses` provided, skip cluster creation and store addresses directly
    - Otherwise, call private method to start cluster
    - _Requirements: 1.3, 1.5, 1.6, 1.7, 1.8, 1.9_

  - [x] 2.4 Implement build_start_args class method for command construction
    - Build command array: `['python3', script_path, ...]`
    - Add `--tls` flag when `tls` is true
    - Add `start` subcommand
    - Add `--cluster-mode` flag when `cluster_mode` is true
    - Add `-n <shard_count>` and `-r <replica_count>` arguments
    - Add `--load-module <path>` for each module in `load_module` array
    - Use array form (not string) to avoid shell injection
    - _Requirements: 1.1, 1.5, 1.6, 1.7, 1.8, 1.9, 6.1, 6.2, 7.3_

  - [x] 2.5 Implement start_cluster private method with subprocess execution
    - Use `Open3.capture3` with command array (not shell string)
    - Check exit status, raise `ClusterStartError` with stderr on failure
    - Parse stdout to extract cluster info
    - Store TLS certificate paths when TLS enabled
    - _Requirements: 1.1, 1.10, 4.1, 4.2_

  - [x] 2.6 Implement parse_output class method for script output parsing
    - Extract `CLUSTER_FOLDER` from output
    - Extract `CLUSTER_NODES` comma-separated list
    - Parse each node as `{host:, port:}` hash with port as Integer
    - Raise `OutputParseError` if required fields missing
    - Return hash with `:cluster_folder` and `:addresses` keys
    - _Requirements: 1.2_

  - [x] 2.7 Implement close method and finalizer for cleanup
    - Build stop command: `['python3', script_path, '--tls' if tls, 'stop', '--cluster-folder', folder]`
    - Use `Open3.capture3` or `system` with output suppressed
    - Suppress cleanup errors silently (don't mask test failures)
    - Clear instance variables after cleanup
    - Register finalizer in initialize using `ObjectSpace.define_finalizer`
    - Undefine finalizer in close to prevent double cleanup
    - _Requirements: 1.4_

  - [ ]* 2.8 Write property test for configuration to arguments mapping (Property 1)
    - **Property 1: Configuration to Command-Line Arguments Mapping**
    - **Validates: Requirements 1.1, 1.5, 1.6, 1.7, 1.8, 1.9, 4.1, 5.1, 5.3, 6.1, 6.2**
    - Use rantly to generate: cluster_mode (boolean), tls (boolean), shard_count (1-100), replica_count (0-10), load_module (0-5 paths)
    - Assert command array structure matches expected format
    - Run 100 iterations minimum

  - [ ]* 2.9 Write property test for output parsing (Property 2)
    - **Property 2: Cluster Manager Output Parsing**
    - **Validates: Requirements 1.2**
    - Use rantly to generate: folder paths, node arrays (1-20 nodes with host:port)
    - Construct synthetic cluster_manager.py output
    - Assert parsed result matches input
    - Run 100 iterations minimum

  - [ ]* 2.10 Write property test for safe path handling (Property 4)
    - **Property 4: Safe Path Handling in Subprocess Commands**
    - **Validates: Requirements 7.3**
    - Use rantly to generate paths with special characters (spaces, quotes, shell metacharacters, unicode)
    - Assert command array isolates paths as single elements
    - Verify array form prevents shell injection
    - Run 100 iterations minimum

  - [ ]* 2.11 Write unit tests for Valkey::TestCluster
    - Test `initialize` with pre-existing addresses skips cluster creation
    - Test `ScriptNotFoundError` raised when script missing
    - Test `PythonNotFoundError` raised when Python 3 unavailable
    - Test `ClusterStartError` with stderr on non-zero exit
    - Test `OutputParseError` on malformed output
    - Test default values (shard_count=3, replica_count=1)
    - Test TLS certificate path exposure when TLS enabled
    - _Requirements: 1.2, 1.3, 1.5, 1.6, 1.7, 1.8, 1.10, 7.1, 7.2_

- [x] 3. Checkpoint - Verify TestCluster implementation
  - Ensure all unit tests pass, ask the user if questions arise.

- [x] 4. Update Helper::Cluster module
  - [x] 4.1 Create test/support/helper/cluster.rb with updated implementation
    - Add class-level `@test_cluster` instance variable
    - Add `cluster_addresses` class method with priority: ENV > dynamic cluster
    - Add `start_cluster` class method to create `Valkey::TestCluster` instance
    - Add `stop_cluster` class method to cleanup
    - _Requirements: 2.1, 2.4, 2.5_

  - [x] 4.2 Implement environment variable support for external endpoints
    - Parse `CLUSTER_ENDPOINTS` env var (format: `host1:port1,host2:port2`)
    - Implement `parse_endpoints` private method
    - Skip cluster creation when external endpoints provided
    - Support `CLUSTER_TLS` env var to enable TLS mode
    - Support `CLUSTER_MODULES` env var for module paths (comma-separated)
    - _Requirements: 2.2, 2.3, 2.6_

  - [ ]* 4.3 Write property test for endpoint string parsing (Property 3)
    - **Property 3: Endpoint String Parsing**
    - **Validates: Requirements 2.2, 5.5**
    - Use rantly to generate endpoint strings (1-20 nodes, valid IP:port pairs)
    - Assert round-trip: `format(parse(s)) == s`
    - Run 100 iterations minimum

  - [ ]* 4.4 Write unit tests for Helper::Cluster
    - Test `cluster_addresses` returns ENV endpoints when set
    - Test `cluster_addresses` creates cluster when no ENV
    - Test `parse_endpoints` handles various formats
    - Test `stop_cluster` calls close on test_cluster
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [x] 5. Update Helper::Client module for standalone support
  - [x] 5.1 Update test/support/helper/client.rb with TestCluster integration
    - Add class-level `@test_server` instance variable
    - Add `server_address` class method with priority: ENV > dynamic server > default localhost:6379
    - Add `start_server` class method using `Valkey::TestCluster.new(cluster_mode: false)`
    - Add `stop_server` class method for cleanup
    - _Requirements: 5.1, 5.2_

  - [x] 5.2 Implement environment variable support for standalone endpoints
    - Parse `STANDALONE_ENDPOINTS` env var
    - Support `STANDALONE_TLS` env var
    - Support `STANDALONE_MODULES` env var
    - Maintain backward compatibility with default localhost:6379
    - _Requirements: 5.5_

  - [ ]* 5.3 Write unit tests for Helper::Client standalone support
    - Test `server_address` returns ENV endpoint when set
    - Test `server_address` returns default when no server started
    - Test `start_server` creates standalone TestCluster
    - _Requirements: 5.1, 5.2, 5.5_

- [x] 6. Checkpoint - Verify test helper integration
  - Ensure all helper tests pass, ask the user if questions arise.

- [x] 7. Update CI workflow for cluster tests
  - [x] 7.1 Update .github/workflows/CI.yml cluster job setup
    - Add Python 3.11 setup step using `actions/setup-python@v5`
    - Add Valkey server installation step (from packages.valkey.io)
    - Remove `services.valkey-cluster` Docker service block
    - Update checkout step to include `submodules: recursive`
    - _Requirements: 3.1, 3.2, 3.3_

  - [x] 7.2 Configure cluster test environment and execution
    - Remove cluster node configuration steps (Docker-specific)
    - Remove "Wait for cluster to be ready" step (handled by TestCluster)
    - Set `CLUSTER_TLS` and `CLUSTER_MODULES` env vars as needed
    - Run `bundle exec rake test:cluster` with new infrastructure
    - _Requirements: 3.4, 3.5_

  - [x] 7.3 Add failure artifact upload for cluster logs
    - Add `actions/upload-artifact@v4` step with `if: failure()`
    - Upload `valkey-glide/utils/clusters/` directory
    - Set retention-days to 7
    - Name artifact with Ruby version matrix variable
    - _Requirements: 3.6_

  - [ ]* 7.4 Write integration test for cluster start/stop lifecycle
    - Test starting 3-shard cluster, verify CLUSTER NODES command works
    - Test stopping cluster and verifying cleanup
    - Test TLS cluster creation when TLS enabled
    - _Requirements: 1.1, 1.4, 4.1, 4.3_

- [x] 8. Update CI workflow for standalone tests (optional)
  - [x] 8.1 Optionally update standalone job to use cluster_manager.py
    - Add Python 3 and Valkey installation (if not using Docker)
    - Set `STANDALONE_ENDPOINTS` or use dynamic server creation
    - Maintain module loading support for JSON/Bloom/Search tests
    - _Requirements: 5.4_

- [x] 9. Wire components together and verify integration
  - [x] 9.1 Update test_helper.rb to require new components
    - Require `valkey/test_cluster` in test setup
    - Ensure Helper::Cluster and Helper::Client are properly loaded
    - Add hooks for cluster/server lifecycle if needed
    - _Requirements: 2.1, 5.2_

  - [x] 9.2 Update existing cluster tests to use new infrastructure
    - Verify `test/cluster/cluster_commands_test.rb` works with new helper
    - Ensure CLUSTER_NODES references updated to use `cluster_addresses`
    - Test module loading for JSON commands in cluster mode
    - _Requirements: 2.5, 6.3_

  - [ ]* 9.3 Write integration tests for end-to-end scenarios
    - Test concurrent clusters can coexist
    - Test cleanup on GC (finalizer verification)
    - Test module loading with actual modules
    - _Requirements: 1.4, 6.1, 6.4_

- [x] 10. Final checkpoint - Full test suite verification
  - Ensure all tests pass (unit, property, integration), ask the user if questions arise.

## Notes

- **Do NOT leave comments in code referencing this spec** - No comments like `# Requirement 1.2`, `# See design.md`, `# Property 3`, etc. The code should be self-documenting and not reference internal planning documents.
- Tasks marked with `*` are optional test sub-tasks that can be skipped for faster MVP
- The `rantly` gem is used for property-based testing (Ruby PBT library)
- Property tests validate universal correctness properties from the design document
- Each property test should run minimum 100 iterations
- TLS certificates are generated by cluster_manager.py in `valkey-glide/utils/tls_crts/`
- The implementation maintains backward compatibility with `CLUSTER_ENDPOINTS` and `STANDALONE_ENDPOINTS` environment variables
- Cleanup errors are suppressed to avoid masking test failures (matching Python implementation behavior)
- Use array form with `Open3.capture3` for subprocess invocation to prevent shell injection

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["2.1"] },
    { "id": 2, "tasks": ["2.2", "2.3"] },
    { "id": 3, "tasks": ["2.4", "2.6"] },
    { "id": 4, "tasks": ["2.5", "2.7"] },
    { "id": 5, "tasks": ["2.8", "2.9", "2.10", "2.11"] },
    { "id": 6, "tasks": ["4.1"] },
    { "id": 7, "tasks": ["4.2", "5.1"] },
    { "id": 8, "tasks": ["4.3", "4.4", "5.2"] },
    { "id": 9, "tasks": ["5.3", "7.1"] },
    { "id": 10, "tasks": ["7.2", "7.3", "7.4"] },
    { "id": 11, "tasks": ["8.1"] },
    { "id": 12, "tasks": ["9.1"] },
    { "id": 13, "tasks": ["9.2"] },
    { "id": 14, "tasks": ["9.3"] }
  ]
}
```
