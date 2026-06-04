# Requirements Document

## Introduction

This feature unifies and improves the test infrastructure for the valkey-glide-ruby project by creating a shared test architecture. Tests in `test/valkey/` become reusable modules (similar to lint/) that can be run in both standalone and cluster contexts. This enables maximum test coverage across both deployment modes with minimal code duplication.

## Glossary

- **Test_Infrastructure**: The combination of test directories, Rake tasks, and CI workflows that execute automated tests for the valkey-glide-ruby gem
- **Lint_Module**: A shared Ruby module in `test/lint/` containing reusable test methods that can be included by both standalone and cluster test classes
- **Valkey_Module**: A shared Ruby module in `test/valkey/` containing reusable test methods (similar to lint modules) that can be included by both standalone and cluster test classes
- **Standalone_Server**: A single Valkey/Redis server instance running on port 6379 (database 15) used for non-cluster tests
- **Cluster_Server**: A 6-node Valkey cluster running on ports 7000-7005 used for cluster-mode tests
- **Rakefile**: The Ruby build configuration file defining Rake tasks including `test:standalone` and `test:cluster`
- **CI_Workflow**: The GitHub Actions workflow file (`.github/workflows/CI.yml`) that runs automated tests on push and pull requests

## Requirements

### Requirement 1: Rename test directory back to valkey

**User Story:** As a developer, I want the test directory renamed from `test/standalone/` back to `test/valkey/` so that these tests become shared modules usable by both standalone and cluster test suites.

#### Acceptance Criteria

1. WHEN the test directory structure is examined, THE Test_Infrastructure SHALL have `test/valkey/` as the shared test modules directory
2. THE Test_Infrastructure SHALL preserve all existing test files and their contents during the rename
3. THE Test_Infrastructure SHALL maintain `test/lint/` as the shared lint modules directory without changes

### Requirement 2: Convert valkey tests to reusable modules

**User Story:** As a developer, I want tests in `test/valkey/` to be refactored into reusable modules that accept a test helper so that they can run in both standalone and cluster modes.

#### Acceptance Criteria

1. THE Test_Infrastructure SHALL convert test files in `test/valkey/` to Ruby modules following the same pattern as lint modules
2. EACH converted module SHALL use the `r` helper method (provided by `Helper::Generic`) to access the Valkey client
3. THE Test_Infrastructure SHALL ensure modules do not directly include `Helper::Client` or `Helper::Cluster`
4. THE Test_Infrastructure SHALL create a loader file that requires all valkey modules (similar to how lint modules are loaded in test_helper.rb)

### Requirement 3: Create new standalone test suite

**User Story:** As a developer, I want a new `test/standalone/` directory that references both lint and valkey modules so that I can run comprehensive tests against a standalone Valkey server.

#### Acceptance Criteria

1. THE Test_Infrastructure SHALL create a `test/standalone/` directory with test class files
2. EACH standalone test class SHALL include `Helper::Client` to connect to standalone Valkey
3. EACH standalone test class SHALL include relevant `Lint::*` modules for command coverage
4. EACH standalone test class SHALL include relevant `Valkey::*` modules for shared test coverage
5. WHEN a developer runs `bundle exec rake test:standalone`, THE Rakefile SHALL execute all tests in the `test/standalone/` directory

### Requirement 4: Update cluster tests to reference valkey modules

**User Story:** As a developer, I want the cluster test suite to include both lint modules and the new valkey modules so that cluster mode has comprehensive test coverage matching standalone.

#### Acceptance Criteria

1. THE Test_Infrastructure SHALL update `test/cluster/` test classes to include relevant `Valkey::*` modules
2. THE Test_Infrastructure SHALL continue to include existing `Lint::*` modules in cluster tests
3. IF a Valkey_Module test fails due to cluster-specific limitations, THEN THE Test_Infrastructure SHALL add skip statements with documentation
4. THE Test_Infrastructure SHALL verify cluster tests use `Helper::Cluster` to connect to the cluster

### Requirement 5: Verify valkey tests pass in cluster mode

**User Story:** As a developer, I want to verify that the shared valkey tests pass when run in cluster mode so that I have confidence both modes have equivalent functionality.

#### Acceptance Criteria

1. WHEN cluster tests are run, THE Test_Infrastructure SHALL execute all included Valkey_Module tests
2. IF a Valkey_Module test is incompatible with cluster mode, THEN THE Test_Infrastructure SHALL skip it with a clear message explaining the limitation
3. THE Test_Infrastructure SHALL document which tests are skipped and why in code comments

### Requirement 6: Update Rakefile and CI workflow

**User Story:** As a developer, I want the Rakefile and CI workflow updated to support the new test structure so that both standalone and cluster tests can be run consistently.

#### Acceptance Criteria

1. WHEN a developer runs `bundle exec rake test:standalone`, THE Rakefile SHALL execute all tests in `test/standalone/`
2. WHEN a developer runs `bundle exec rake test:cluster`, THE Rakefile SHALL execute all tests in `test/cluster/`
3. WHEN a developer runs `bundle exec rake test`, THE Rakefile SHALL execute both test suites
4. THE Rakefile SHALL validate that no test files exist outside defined test groups
5. THE CI_Workflow SHALL execute `bundle exec rake test:standalone` for standalone tests
6. THE CI_Workflow SHALL preserve all existing CI job configurations (Ruby versions, Valkey versions, module loading, SSL setup)
