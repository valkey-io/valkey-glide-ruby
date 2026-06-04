# Design Document: Test Cluster Unification

## Overview

This design document describes the architectural changes needed to unify and improve the test infrastructure for the valkey-glide-ruby project. The implementation creates a shared test architecture where tests in `test/valkey/` become reusable modules (similar to lint/) that can be run in both standalone and cluster contexts.

## Architecture

### Current Test Structure

```
test/
├── standalone/           # Standalone server tests (direct test classes)
│   ├── *_commands_test.rb    # Include Helper::Client directly
│   ├── test_opentelemetry.rb
│   ├── test_statistics.rb
│   └── uri_connection_test.rb
├── cluster/              # Cluster mode tests
│   └── cluster_commands_test.rb
├── lint/                 # Shared test modules
│   ├── *_commands.rb     # Modules included by test classes
│   └── ...
├── support/
│   └── helper/
│       ├── client.rb     # Standalone helper
│       ├── cluster.rb    # Cluster helper
│       └── generic.rb    # Shared helper methods
└── test_helper.rb
```

### Target Test Structure

```
test/
├── valkey/               # Shared test MODULES (like lint/)
│   ├── opentelemetry.rb      # Module: Valkey::OpenTelemetry
│   ├── statistics.rb         # Module: Valkey::Statistics
│   ├── uri_connection.rb     # Module: Valkey::URIConnection
│   ├── generic_commands.rb   # Module: Valkey::GenericCommands
│   └── ...                   # Other test modules
├── standalone/           # Standalone test CLASSES
│   ├── test_commands.rb      # Includes Helper::Client + Lint::* + Valkey::*
│   ├── test_opentelemetry.rb # Includes Helper::Client + Valkey::OpenTelemetry
│   └── ...
├── cluster/              # Cluster test CLASSES
│   ├── cluster_commands_test.rb  # Includes Helper::Cluster + Lint::* + Valkey::*
│   └── ...
├── lint/                 # Unchanged - existing lint modules
├── support/              # Unchanged
└── test_helper.rb        # Updated to load valkey/ modules
```

## Components and Interfaces

### 1. Directory Rename and Module Conversion

**Purpose:** Rename `test/standalone/` to `test/valkey/` and convert test classes to reusable modules.

**Implementation Pattern:**

Before (test class in `test/standalone/generic_commands_test.rb`):
```ruby
# frozen_string_literal: true

require "test_helper"

class TestGenericCommands < Minitest::Test
  include Helper::Client
  include Lint::GenericCommands

  def test_randomkey
    # ... test implementation
  end
end
```

After (module in `test/valkey/generic_commands.rb`):
```ruby
# frozen_string_literal: true

module Valkey
  module GenericCommands
    # Tests specific to valkey-glide-ruby (beyond lint coverage)
    def test_randomkey
      # ... test implementation using `r` helper
    end
  end
end
```

### 2. Standalone Test Suite (`test/standalone/`)

**Purpose:** Create a new test suite that combines lint modules and valkey modules with standalone helper.

**Implementation:**
```ruby
# test/standalone/commands_test.rb
# frozen_string_literal: true

require "test_helper"

class TestStandaloneCommands < Minitest::Test
  include Helper::Client
  
  # Lint modules for redis-rb compatibility
  include Lint::StringCommands
  include Lint::HashCommands
  include Lint::ListCommands
  include Lint::SetCommands
  include Lint::SortedSetCommands
  include Lint::StreamCommands
  include Lint::GenericCommands
  include Lint::BitmapCommands
  include Lint::GeoCommands
  include Lint::HyperLogLogCommands
  include Lint::ScriptingCommands
  include Lint::ServerCommands
  include Lint::ConnectionCommands
  include Lint::ConnectionOptions
  include Lint::PubSubCommands
  include Lint::FunctionCommands
  include Lint::ModuleCommands
  include Lint::JsonCommands
  include Lint::TransactionCommands
  include Lint::VectorSearchCommands
  
  # Valkey-specific test modules
  include Valkey::GenericCommands
  # ... other Valkey::* modules
end

# test/standalone/test_opentelemetry.rb
class TestStandaloneOpenTelemetry < Minitest::Test
  include Helper::Client
  include Valkey::OpenTelemetry
end
```

### 3. Cluster Test Suite Updates

**Purpose:** Update cluster tests to include valkey modules for shared test coverage.

**Implementation:**
```ruby
# test/cluster/cluster_commands_test.rb
# frozen_string_literal: true

require "test_helper"

class TestClusterCommands < Minitest::Test
  include Helper::Cluster
  
  # Lint modules (cluster-compatible)
  include Lint::StringCommands
  include Lint::HashCommands
  include Lint::ListCommands
  include Lint::SetCommands
  include Lint::SortedSetCommands
  include Lint::StreamCommands
  include Lint::GenericCommands
  include Lint::BitmapCommands
  include Lint::GeoCommands
  include Lint::HyperLogLogCommands
  include Lint::ScriptingCommands
  include Lint::ServerCommands
  include Lint::ConnectionCommands
  include Lint::ConnectionOptions
  include Lint::PubSubCommands
  include Lint::FunctionCommands
  include Lint::ModuleCommands
  include Lint::JsonCommands
  include Lint::ClusterCommands
  
  # Valkey-specific test modules (cluster-compatible)
  include Valkey::GenericCommands
  # ... other Valkey::* modules (with skip statements for cluster-incompatible tests)
end

# test/cluster/test_opentelemetry.rb (if OTel is cluster-compatible)
class TestClusterOpenTelemetry < Minitest::Test
  include Helper::Cluster
  include Valkey::OpenTelemetry
end
```

### 4. Test Helper Updates

**Purpose:** Load valkey modules similar to how lint modules are loaded.

**Implementation:**
```ruby
# test/test_helper.rb additions
# ... existing content ...

# Load lint modules
Dir[File.expand_path("lint/**/*.rb", __dir__)].sort.each do |f|
  require f
end

# Load valkey shared test modules
Dir[File.expand_path("valkey/**/*.rb", __dir__)].sort.each do |f|
  require f
end
```

## Data Models

### Module Namespace Structure

| Location | Namespace | Purpose |
|----------|-----------|---------|
| `test/lint/` | `Lint::*` | redis-rb compatibility tests |
| `test/valkey/` | `Valkey::*` | valkey-glide-ruby specific tests |

### Helper Module Selection

| Test Directory | Helper Module | Description |
|----------------|---------------|-------------|
| `test/standalone/` | `Helper::Client` | Standalone server (localhost:6379, DB 15) |
| `test/cluster/` | `Helper::Cluster` | 6-node cluster (127.0.0.1:7000-7005) |

### Test File Transformation

| Original File | Module Name | Notes |
|--------------|-------------|-------|
| `test/standalone/generic_commands_test.rb` | `Valkey::GenericCommands` | Extra tests beyond `Lint::GenericCommands` |
| `test/standalone/test_opentelemetry.rb` | `Valkey::OpenTelemetry` | OTel integration tests |
| `test/standalone/test_statistics.rb` | `Valkey::Statistics` | Statistics API tests |
| `test/standalone/uri_connection_test.rb` | `Valkey::URIConnection` | URI parsing tests |
| `test/standalone/scanning_test.rb` | `Valkey::Scanning` | SCAN operation tests |
| `test/standalone/sorting_test.rb` | `Valkey::Sorting` | SORT operation tests |
| `test/standalone/bitpos_test.rb` | `Valkey::Bitpos` | BITPOS tests |
| `test/standalone/utils_test.rb` | `Valkey::Utils` | Utility function tests |

### Cluster Compatibility Matrix

| Valkey Module | Standalone | Cluster | Notes |
|---------------|------------|---------|-------|
| GenericCommands | ✓ | ✓* | Skip multi-db tests |
| OpenTelemetry | ✓ | ✓ | OTel is process-wide |
| Statistics | ✓ | ✓ | Client-side metrics |
| URIConnection | ✓ | ✓* | Skip single-host tests |
| Scanning | ✓ | ✓* | Use SCAN per node or hash tags |
| Sorting | ✓ | ✓* | Use hash tags |
| Bitpos | ✓ | ✓ | Single key operations |
| Utils | ✓ | ✓ | Utility tests |

\* = Some tests may need skip statements for cluster compatibility

## Interfaces

### Rake Task Interface

```bash
# Run standalone tests
bundle exec rake test:standalone

# Run cluster tests
bundle exec rake test:cluster

# Run all tests
bundle exec rake test

# Verbose mode
CI=1 bundle exec rake test:standalone
VERBOSE=1 bundle exec rake test:cluster
```

### Test Module Interface

All test modules follow the same pattern:

```ruby
module Valkey
  module ModuleName
    # Use `r` to access the Valkey client (provided by Helper::Generic)
    def test_feature
      r.set("key", "value")
      assert_equal "value", r.get("key")
    end
    
    # Use `skip` for cluster-incompatible tests
    def test_standalone_only_feature
      skip("Not supported in cluster mode") if cluster_mode?
      # ... standalone-only test
    end
    
    # Use `cluster_mode?` method (provided by Helper::Client/Helper::Cluster)
    def test_mode_aware_feature
      if cluster_mode?
        # cluster-specific behavior
      else
        # standalone-specific behavior
      end
    end
  end
end
```

## Error Handling

### Cluster-Specific Test Skips

Tests that cannot run in cluster mode should use `skip` with clear documentation:

```ruby
def test_select_database
  skip("Database selection not supported in cluster mode") if cluster_mode?
  r.select(1)
  # ...
end

def test_move_key
  skip("MOVE command not supported in cluster mode") if cluster_mode?
  # ...
end
```

### Module Load Order

The test helper loads modules in a specific order to ensure dependencies are available:

1. `test/support/helper/*.rb` - Helper modules
2. `test/lint/**/*.rb` - Lint modules
3. `test/valkey/**/*.rb` - Valkey modules

## Testing Strategy

### Verification Steps

1. **Rename verification:**
   - `test/valkey/` exists with converted modules
   - `test/standalone/` exists with new test classes
   - No test class files remain in `test/valkey/`

2. **Standalone tests pass:**
   - `bundle exec rake test:standalone` completes successfully
   - All lint modules included
   - All valkey modules included

3. **Cluster tests pass:**
   - `bundle exec rake test:cluster` completes successfully
   - Valkey modules included with appropriate skips
   - No cluster-incompatible tests fail

4. **Full suite verification:**
   - `bundle exec rake test` runs both suites
   - No orphaned test files
