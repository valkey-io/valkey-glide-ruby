# frozen_string_literal: true

# SimpleCov configuration
SimpleCov.configure do
  enable_coverage :branch
  primary_coverage :line
  command_name "test-#{ENV['COV_GROUP'] || 'all'}"
  merging true
  merge_timeout 3600

  skip %r{^/test/}
  skip %r{^/valkey-glide/} # vendored upstream submodule, not our code
  cover "lib/**/*.rb" # includes unloaded lib files and restricts the report to them

  # Ideally, we aim for 80% coverage, which at this time is lower.
  # Should we make coverage improvements, please bump this number.
  expected_coverage line: 40, branch: 10
end
