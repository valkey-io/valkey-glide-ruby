# frozen_string_literal: true

require "test_helper"

class TestModuleCommands < Minitest::Test
  include Helper::Client
  include Lint::ModuleCommands
end
