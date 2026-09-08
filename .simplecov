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

  # tracked in https://github.com/valkey-io/valkey-glide-ruby/issues/307
  # reference_config = RUBY_PLATFORM.start_with?("x86_64-linux") &&
  #                    RUBY_VERSION.start_with?("3.4") &&
  #                    ENV["ENGINE_VERSION"] == "9.0"

  # cluster runs last, so its report is the merge of all three suites.
  project_total = suite == "cluster"

  if reference_config && project_total
    minimum_coverage line: 88.87, branch: 72.5
    maximum_coverage line: 88.87
  end
end
