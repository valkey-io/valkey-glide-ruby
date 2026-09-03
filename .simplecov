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

  # We aims for a minimum of 80% coverage. However, our coverage at this time is much lower than this.
  # Improvement is tracked in https://github.com/valkey-io/valkey-glide-ruby/issues/307
  minimum_coverage line: 40, branch: 10
end
