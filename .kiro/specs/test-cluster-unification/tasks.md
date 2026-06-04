# Implementation Plan: Test Cluster Unification

## Overview

This implementation plan creates a shared test architecture where tests in `test/valkey/` become reusable modules (similar to lint/) that can be run in both standalone and cluster contexts. This enables maximum test coverage across both deployment modes with minimal code duplication.

## Tasks

- [x] 1. Rename standalone to valkey and convert tests to modules
  - [x] 1.1 Rename `test/standalone/` to `test/valkey/` using git mv
    - Execute `git mv test/standalone test/valkey`
    - Verify all test files are preserved
    - _Requirements: 1.1, 1.2, 1.3_

  - [x] 1.2 Convert test classes in `test/valkey/` to reusable modules
    - Rename files from `*_test.rb` to `*.rb` (module naming convention)
    - Change `class TestFoo < Minitest::Test` to `module Valkey::Foo`
    - Remove `include Helper::Client` from each module (helper provided by including class)
    - Remove `require "test_helper"` (modules are loaded by test_helper.rb)
    - Keep test methods and any standalone-only skips
    - Files to convert: `generic_commands_test.rb`, `test_opentelemetry.rb`, `test_statistics.rb`, `uri_connection_test.rb`, `scanning_test.rb`, `sorting_test.rb`, `bitpos_test.rb`, `utils_test.rb`
    - Files that only include Lint modules can be deleted (e.g., `string_commands_test.rb`)
    - _Requirements: 2.1, 2.2, 2.3_

  - [x] 1.3 Update `test/test_helper.rb` to load valkey modules
    - Add loader block similar to lint modules: `Dir[File.expand_path("valkey/**/*.rb", __dir__)].sort.each { |f| require f }`
    - _Requirements: 2.4_

- [x] 2. Checkpoint - Verify module conversion
  - Run `ruby -c test/valkey/*.rb` to check syntax
  - Verify no test classes remain in `test/valkey/`
  - Ensure all tests pass, ask the user if questions arise

- [x] 3. Create new standalone test suite
  - [x] 3.1 Create `test/standalone/` directory with test class files
    - Create `test/standalone/commands_test.rb` with `Helper::Client` and all `Lint::*` modules
    - Create `test/standalone/valkey_test.rb` with `Helper::Client` and all `Valkey::*` modules
    - Or create separate files per module group for better organization
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [x] 3.2 Verify Rakefile already supports `test:standalone`
    - Confirm `groups = %i[standalone cluster]` already exists
    - Confirm task runs tests from `test/standalone/**/*_test.rb`
    - _Requirements: 3.5, 6.1_

- [x] 4. Checkpoint - Verify standalone tests pass
  - Run `bundle exec rake test:standalone`
  - Ensure all tests pass, ask the user if questions arise

- [x] 5. Update cluster tests to include valkey modules
  - [x] 5.1 Add Valkey modules to `test/cluster/cluster_commands_test.rb`
    - Add `include Valkey::GenericCommands` (with skips for multi-db tests)
    - Add `include Valkey::Statistics` (client-side metrics work in cluster)
    - Add `include Valkey::URIConnection` (with skips for single-host tests)
    - Add other compatible Valkey modules with appropriate skips
    - _Requirements: 4.1, 4.2_

  - [x] 5.2 Add skip statements for cluster-incompatible tests
    - Add `skip("Not supported in cluster mode") if cluster_mode?` where needed
    - Document skipped tests with clear reasons
    - Focus on: database selection, MOVE command, single-host URI tests
    - _Requirements: 4.3, 5.2_

  - [x] 5.3 Add remaining Lint modules to cluster tests
    - Uncomment `Lint::StringCommands` (already has hash tags)
    - Uncomment `Lint::ServerCommands`
    - Add `Lint::GenericCommands`
    - Add `Lint::ListCommands`
    - Add `Lint::SetCommands`
    - Add `Lint::SortedSetCommands`
    - Add `Lint::BitmapCommands`
    - Add `Lint::GeoCommands`
    - Add `Lint::HyperLogLogCommands`
    - Add `Lint::ScriptingCommands`
    - _Requirements: 4.2, 4.4_

- [x] 6. Checkpoint - Verify cluster tests pass
  - Run `bundle exec rake test:cluster`
  - Document any tests that needed to be skipped
  - Ensure all tests pass, ask the user if questions arise

- [x] 7. Final verification and CI update
  - [x] 7.1 Run full test suite
    - Execute `bundle exec rake test` to run both `test:standalone` and `test:cluster`
    - Verify no orphaned test files (Rakefile lost_tests check)
    - _Requirements: 6.3, 6.4_

  - [x] 7.2 Update CI workflow if needed
    - Verify CI.yml runs `bundle exec rake test:standalone` (should already be correct)
    - Confirm job configurations are preserved
    - _Requirements: 6.5, 6.6_

- [x] 8. Final checkpoint - Complete verification
  - Ensure all tests pass in both modes
  - Ask the user if questions arise

## Notes

- The key insight is that `test/valkey/` becomes like `test/lint/` - a directory of reusable modules
- `test/standalone/` and `test/cluster/` contain test CLASSES that include the modules
- Test classes provide the helper (`Helper::Client` or `Helper::Cluster`) which supplies the `r` method
- Modules use `cluster_mode?` method to conditionally skip incompatible tests
- Files that only include a single Lint module (e.g., `string_commands_test.rb` which just includes `Lint::StringCommands`) can be deleted since the standalone test class will include the Lint module directly
- Each task references specific requirements for traceability

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2"] },
    { "id": 2, "tasks": ["1.3"] },
    { "id": 3, "tasks": ["3.1", "3.2"] },
    { "id": 4, "tasks": ["5.1", "5.2", "5.3"] },
    { "id": 5, "tasks": ["7.1", "7.2"] }
  ]
}
```
