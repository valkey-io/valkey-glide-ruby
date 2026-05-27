# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

# =============================================================================
# Native Library Build Tasks
# =============================================================================

def native_lib_ext
  case RbConfig::CONFIG['host_os']
  when /darwin/
    'dylib'
  else
    'so'
  end
end

namespace :native do
  desc "Initialize the valkey-glide submodule"
  task :submodule do
    puts "Initializing valkey-glide submodule..."
    sh "git submodule update --init --recursive"
  end

  desc "Build the native FFI library (release mode)"
  task build: :submodule do
    puts "Building native FFI library..."
    Dir.chdir("valkey-glide/ffi") do
      sh "cargo build --release"
    end
    puts "Native library built successfully!"
    puts "Location: valkey-glide/ffi/target/release/libglide_ffi.#{native_lib_ext}"
  end

  desc "Build the native FFI library (debug mode)"
  task build_debug: :submodule do
    puts "Building native FFI library (debug)..."
    Dir.chdir("valkey-glide/ffi") do
      sh "cargo build"
    end
    puts "Native library built successfully!"
    puts "Location: valkey-glide/ffi/target/debug/libglide_ffi.#{native_lib_ext}"
  end

  desc "Clean native build artifacts"
  task :clean do
    puts "Cleaning native build artifacts..."
    if Dir.exist?("valkey-glide/ffi")
      Dir.chdir("valkey-glide/ffi") do
        sh "cargo clean"
      end
    end
    puts "Clean complete!"
  end

  desc "Copy built library to lib/valkey for gem packaging"
  task package: :build do
    require 'fileutils'
    src = "valkey-glide/ffi/target/release/libglide_ffi.#{native_lib_ext}"
    dest = "lib/valkey/libglide_ffi.#{native_lib_ext}"

    if File.exist?(src)
      FileUtils.cp(src, dest)
      puts "Copied #{src} to #{dest}"
    else
      abort "Native library not found at #{src}. Run 'rake native:build' first."
    end
  end
end

desc "Build the native FFI library"
task native: "native:build"

# =============================================================================
# Test Tasks
# =============================================================================

namespace :test do
  groups = %i[valkey cluster]
  groups.each do |group|
    Rake::TestTask.new(group) do |t|
      t.libs << "test"
      # Only add local lib to load path when not testing installed gem
      t.libs << "lib" unless ENV["TEST_INSTALLED_GEM"]
      t.test_files = FileList["test/#{group}/**/*_test.rb"]
      t.options = '-v' if ENV['CI'] || ENV['VERBOSE']
    end
  end

  lost_tests = Dir["test/**/*_test.rb"] - groups.map { |g| Dir["test/#{g}/**/*_test.rb"] }.flatten
  abort "The following test files are in no group:\n#{lost_tests.join("\n")}" unless lost_tests.empty?
end

task test: ["test:valkey"]

task default: :test
