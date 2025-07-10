# frozen_string_literal: true

require_relative "lib/valkey/version"

Gem::Specification.new do |spec|
  spec.name = "valkey"
  spec.version = Valkey::VERSION
  spec.authors = ["Mohsen Alizadeh"]
  spec.email = ["mohsen@alizadeh.us"]

  spec.summary = "A Ruby client library for Valkey based on redis-rb."
  spec.description = "A Ruby client library for Valkey based on redis-rb."
  spec.homepage = "https://github.com/mohsen-alizadeh/valkey-rb"
  spec.required_ruby_version = '>= 2.6.0'

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "ffi", "~> 1.17.0"
  spec.add_dependency "google-protobuf", "~> 3.23", ">= 3.23.4"
end
