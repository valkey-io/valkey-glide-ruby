# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create do |t|
  t.verbose = true
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[test rubocop]
