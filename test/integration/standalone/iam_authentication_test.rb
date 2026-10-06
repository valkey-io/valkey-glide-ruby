# frozen_string_literal: true

require "test_helper"

class TestStandaloneIamAuthentication < Minitest::Test
  include Helper::Client
  include ValkeyTests::IamAuthentication
end
