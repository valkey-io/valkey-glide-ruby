# Requirements Document

## Introduction

This document defines the requirements for aligning the valkey-glide-ruby client's cluster testing infrastructure with other GLIDE clients (Python, Java, Node.js, Go). Currently, the Ruby client uses a Docker-based solution (`grokzen/redis-cluster:7.0.15`) for cluster tests in CI, while other GLIDE clients use a shared Python script (`cluster_manager.py`) located in the `valkey-glide/utils/` directory.

The `cluster_manager.py` script provides programmatic control over Valkey/Redis cluster lifecycle, including:
- Starting standalone or cluster-mode servers on dynamically allocated ports
- Generating TLS certificates for secure testing
- Managing replication topology
- Stopping clusters and cleaning up resources

Aligning with this approach provides consistency across GLIDE clients, better control over test cluster configuration, native Valkey server support (instead of Redis), and more flexible port allocation.

## Glossary

- **Cluster_Manager**: The shared Python script (`cluster_manager.py`) located in `valkey-glide/utils/` that other GLIDE clients use to manage test server lifecycle
- **Valkey_Cluster**: A Ruby wrapper class that invokes Cluster_Manager to start and stop test clusters, providing cluster addresses and cleanup capabilities
- **CI_Workflow**: The GitHub Actions workflow (`.github/workflows/CI.yml`) that runs automated tests
- **Standalone_Mode**: A Valkey server running without cluster features, typically on a single port
- **Cluster_Mode**: A Valkey deployment with multiple nodes using Redis Cluster protocol, with hash slot distribution
- **TLS_Mode**: Running Valkey servers with Transport Layer Security enabled for encrypted connections
- **Docker_Cluster**: The current approach using `grokzen/redis-cluster:7.0.15` Docker image for cluster tests

## Requirements

### Requirement 1: Valkey Cluster Wrapper Class

**User Story:** As a developer running tests, I want a Ruby wrapper class that invokes the cluster_manager.py script, so that I can programmatically start and stop Valkey clusters without Docker.

#### Acceptance Criteria

1. THE Valkey_Cluster SHALL initialize by invoking `cluster_manager.py start` with appropriate arguments via subprocess
2. WHEN the Cluster_Manager returns output containing `CLUSTER_FOLDER` and `CLUSTER_NODES`, THE Valkey_Cluster SHALL parse these values and expose cluster addresses as an array of `{host:, port:}` hashes
3. WHEN an existing cluster address array is provided to the constructor, THE Valkey_Cluster SHALL skip cluster creation and use the provided addresses
4. WHEN the Valkey_Cluster object is garbage collected or explicitly closed, THE Valkey_Cluster SHALL invoke `cluster_manager.py stop --cluster-folder <folder>` to clean up resources, suppressing any cleanup errors silently
5. THE Valkey_Cluster SHALL support a `cluster_mode` parameter that adds `--cluster-mode` flag when true
6. THE Valkey_Cluster SHALL support a `tls` parameter that adds `--tls` flag when true
7. THE Valkey_Cluster SHALL support a `shard_count` parameter that maps to the `-n` flag (default: 3)
8. THE Valkey_Cluster SHALL support a `replica_count` parameter that maps to the `-r` flag (default: 1)
9. THE Valkey_Cluster SHALL support a `load_module` parameter that adds `--load-module <path>` for each module path provided
10. IF the cluster_manager.py script returns a non-zero exit code, THEN THE Valkey_Cluster SHALL raise an exception with the error output

### Requirement 2: Test Helper Integration

**User Story:** As a test author, I want the test helpers to automatically use Valkey_Cluster for cluster tests, so that tests can run against dynamically created clusters.

#### Acceptance Criteria

1. THE Helper::Cluster module SHALL create a Valkey_Cluster instance before running cluster tests when no external cluster endpoints are provided
2. THE Helper::Cluster module SHALL support environment variables to specify external cluster endpoints (e.g., `CLUSTER_ENDPOINTS`)
3. WHEN external cluster endpoints are provided via environment variables, THE Helper::Cluster module SHALL skip cluster creation and use the provided endpoints
4. THE Helper::Cluster module SHALL stop and clean up the cluster after all cluster tests complete
5. THE Helper::Cluster module SHALL expose the cluster addresses through a method compatible with the existing `CLUSTER_NODES` constant usage
6. THE Helper::Cluster module SHALL support a `CLUSTER_TLS` environment variable to enable TLS mode for dynamically created clusters

### Requirement 3: CI Workflow Updates

**User Story:** As a CI maintainer, I want the cluster tests to use cluster_manager.py instead of Docker, so that the Ruby client aligns with other GLIDE clients.

#### Acceptance Criteria

1. THE CI_Workflow SHALL install Python 3 as a prerequisite for cluster tests
2. THE CI_Workflow SHALL install Valkey server from source or package before running cluster tests
3. THE CI_Workflow SHALL remove the Docker `grokzen/redis-cluster` service from cluster test jobs
4. THE CI_Workflow SHALL set appropriate environment variables to configure cluster creation (TLS, modules, etc.)
5. WHEN cluster tests complete, THE CI_Workflow SHALL allow the test teardown to clean up cluster resources via cluster_manager.py
6. THE CI_Workflow SHALL upload cluster logs from the cluster folder as artifacts on test failure for debugging

### Requirement 4: TLS Cluster Testing Support

**User Story:** As a developer, I want to run cluster tests with TLS enabled using cluster_manager.py, so that I can verify secure cluster connections.

#### Acceptance Criteria

1. WHEN TLS mode is enabled, THE Valkey_Cluster SHALL pass `--tls` flag to cluster_manager.py, failing fast with an error if the flag cannot be passed
2. THE Valkey_Cluster SHALL expose the TLS certificate paths generated by cluster_manager.py
3. THE Helper::Cluster module SHALL configure the Valkey client with appropriate TLS options when TLS mode is enabled
4. THE CI_Workflow SHALL support a matrix option to run cluster tests with TLS enabled

### Requirement 5: Standalone Server Support

**User Story:** As a developer, I want to use cluster_manager.py for standalone server tests too, so that all server lifecycle management is consistent with other GLIDE clients.

#### Acceptance Criteria

1. WHEN cluster_mode is false or omitted, THE Valkey_Cluster SHALL start a standalone Valkey server (no cluster features)
2. THE test helpers SHALL support using Valkey_Cluster for standalone server tests when no external server endpoint is provided via environment variables
3. THE Valkey_Cluster SHALL support replication setup for standalone mode when replica_count is greater than 0
4. THE CI_Workflow SHALL use cluster_manager.py for standalone tests, replacing the Docker-based standalone server
5. THE test helpers SHALL support environment variables to specify external standalone endpoints (e.g., `STANDALONE_ENDPOINTS`)

### Requirement 6: Module Loading Support

**User Story:** As a developer testing module features (JSON, Bloom, Search), I want cluster_manager.py to load modules into test servers, so that module tests work with dynamically created clusters.

#### Acceptance Criteria

1. THE Valkey_Cluster SHALL accept an array of module paths via the `load_module` parameter
2. WHEN module paths are provided, THE Valkey_Cluster SHALL pass each path to cluster_manager.py using `--load-module <path>`
3. THE CI_Workflow SHALL configure module paths for module-specific tests (JSON, Bloom, Search)
4. IF a module file does not exist at the specified path, THEN THE Valkey_Cluster SHALL allow cluster_manager.py to report the error

### Requirement 7: Script Path Resolution

**User Story:** As a developer, I want the Valkey_Cluster to correctly locate cluster_manager.py in the valkey-glide submodule, so that the script can be invoked from any working directory.

#### Acceptance Criteria

1. THE Valkey_Cluster SHALL resolve the path to cluster_manager.py relative to the valkey-glide submodule location, raising an error if the path to the valkey-glide submodule cannot be resolved
2. IF the cluster_manager.py script is not found at the expected path, THEN THE Valkey_Cluster SHALL raise an informative error message
3. THE Valkey_Cluster SHALL escape or handle paths with spaces or special characters before invoking subprocess commands to prevent errors
