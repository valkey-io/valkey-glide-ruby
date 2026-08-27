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

  # Ideally, branch should be at 80. However at the time of writing the coverage sits
  # slightly above 65. We should increase this overtime.
  minimum_coverage line: 80, branch: 65
end
