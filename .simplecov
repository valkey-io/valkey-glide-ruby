# frozen_string_literal: true

# SimpleCov configuration
SimpleCov.configure do
  suite = ENV["COV_GROUP"] || "all"

  enable_coverage :branch
  primary_coverage :line
  command_name "test-#{suite}"
  merging true
  merge_timeout 3600

  skip %r{^/test/}
  skip %r{^/valkey-glide/} # vendored upstream submodule, not our code
  cover "lib/**/*.rb" # includes unloaded lib files and restricts the report to them

  # Ideally, we aim for 80% coverage, which at this time is lower.
  expected = {
    "unit" => { line: 51.11, branch: 17.41 },
    "standalone" => { line: 85.08, branch: 67.09 },
    "cluster" => { line: 76.80, branch: 49.30 }
  }

  # Different configurations have different coverage. We enforce on the latest
  # for now. See https://github.com/valkey-io/valkey-glide-ruby/issues/307
  reference_config = RUBY_PLATFORM.include?("linux") &&
                     RUBY_VERSION.start_with?("3.4") &&
                     ENV["ENGINE_VERSION"] == "9.0"

  if reference_config && expected.key?(suite)
    # Ideally this should be removed once we reached the minimum coverage
    expected_coverage expected.fetch(suite)
  else
    minimum_coverage line: 80, branch: 80
  end
end
